#!/usr/bin/env python3
"""Measure all 39 lab configurations in isolated, resumable scratch directories."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import gzip
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import traceback

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import build
from scripts.build_tools import TECH_LIBS

FLUX = Path("/common/users/shared/fluxlab-tools")
YOSYS = FLUX / "yosys-0.69/bin/yosys"
STA = FLUX / "opensta-2.2.0/bin/sta"
VERILATOR = FLUX / "verilator-nightly6oct/bin/verilator"
ARCH = {"single": "rv32i-single-cycle", "multi": "rv32i-multi-cycle", "pipe": "rv32i-three-stage"}
SUITE = "fib gcd popcount crc32 histogram sieve127 sqrt low-ilp high-ilp low-energy high-energy".split()


def command(argv, cwd, env, log):
    with log.open("w") as out:
        subprocess.run(argv, cwd=cwd, env={**os.environ, **env}, stdout=out,
                       stderr=subprocess.STDOUT, check=True)


def compress(src, dst):
    pending = dst.with_suffix(".pending")
    with src.open("rb") as source, gzip.open(pending, "wb", compresslevel=2) as out:
        shutil.copyfileobj(source, out)
    pending.replace(dst)


def save_report(src, dst):
    # Publishing a completed report is the resume marker for this stage.
    pending = dst.with_suffix(".pending")
    shutil.copyfile(src, pending)
    pending.replace(dst)


def config_job(spec, args):
    size, lib, scope, arch = spec
    name = f"{size}/{lib}/{scope}-{arch}"
    stage = args.scratch / name
    stage.mkdir(parents=True, exist_ok=True)
    with (stage / "measurement.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        run_config(size, lib, scope, arch, stage, args.results / name, args)


def run_config(size, lib, scope, arch, stage, result, args):
    name = f"{size}/{lib}/{scope}-{arch}"
    result.mkdir(parents=True, exist_ok=True)
    # A separate header and working directory prevents cross-size cache hits.
    if not (stage / "src").exists():
        shutil.copytree(ROOT / "src", stage / "src")
        h = stage / "src/rv32i-memory/config.vh"
        txt, n = re.subn(r"(RAM_SIZE_BYTES\s*=\s*)256\b", rf"\g<1>{size}", h.read_text())
        if n != 1:
            raise RuntimeError("Expected default RAM size 256")
        h.write_text(txt)
    if not (stage / "scripts").exists():
        (stage / "scripts").symlink_to(ROOT / "scripts", target_is_directory=True)
    tname = ARCH[arch] + ("-single-bus" if (scope, arch) == ("cpu", "multi") else "") + "-" + scope
    t = build.configure_cpu_build()[tname]
    tech = TECH_LIBS[lib]
    net = stage / "netlist.v"
    if args.compile_only:
        if net.exists():
            compile_model(t, tech, name, stage, args, prefetch=True)
        return
    if not net.exists():
        print(f"synthesis {name}", flush=True)
        tmpnet = stage / "building-netlist.v"
        command([YOSYS, "-c", "scripts/yosys.tcl"], stage, dict(
            # Yosys 0.69 recognizes the echoed interactive ABC prompt.
            # A short TMPDIR keeps readline from eliding its command prefix.
            TMPDIR="/tmp", SYNTH_OUTDIR=str(stage), SYNTH_SOURCE_FILES=t["sources"], SYNTH_TOP_NAME=t["top"],
            SYNTH_TECHLIB_FILE=tech["lib"], SYNTH_NETLIST_FILE=str(tmpnet),
            SYNTH_FLATTEN_EARLY="1"), stage / "synthesis.log")
        tmpnet.replace(net)
    if not (result / "synthesis.log.gz").exists():
        compress(stage / "synthesis.log", result / "synthesis.log.gz")
    staenv = dict(STA_OUTDIR=str(stage), STA_SOURCE_FILES=str(net), STA_TOP_NAME=t["top"],
                  STA_TECHLIB_FILE=tech["lib"], STA_SDC_FILE=t["sdc"], STA_CLOCK_PERIOD="0.0",
                  STA_TIMING_REPORT_NAME="period.rpt")
    if not (result / "period.rpt").exists():
        print(f"timing {name}", flush=True)
        command([STA, "-no_splash", "-exit", "scripts/opensta-timing.tcl"], stage, staenv, stage / "timing.log")
        if "Error:" in (stage / "timing.log").read_text():
            raise RuntimeError(f"Timing failed at {stage}")
        compress(stage / "timing-longest-paths.rpt", result / "paths.rpt.gz")
        shutil.copy(stage / "units.log", result / "units.log")
        if not float((stage / "period.rpt").read_text()) > 0:
            raise ValueError(f"Invalid minimum period at {stage}")
        save_report(stage / "period.rpt", result / "period.rpt")
    staenv.update(STA_CLOCK_PERIOD=(result / "period.rpt").read_text().strip(), STA_TB_DUT_NAME=t["tb top"])
    if not (result / "statistical.rpt").exists():
        command([STA, "-no_splash", "-exit", "scripts/opensta-power.tcl"], stage,
                {**staenv, "STA_POWER_TYPE":"0", "STA_VCD_FILENAME":"none", "STA_POWER_REPORT_NAME":"statistical.rpt"},
                stage / "statistical.log")
        if "Error:" in (stage / "statistical.log").read_text():
            raise RuntimeError(f"Statistical power failed at {stage}")
        if "100.0%" not in (stage / "statistical.rpt").read_text():
            raise ValueError(f"Incomplete statistical power report at {stage}")
        save_report(stage / "statistical.rpt", result / "statistical.rpt")
    if args.static_only or all((result / f"{w}.power.rpt").exists() for w in SUITE):
        return
    simulate(t, tech, name, stage, result, staenv, args)


def compile_model(t, tech, name, stage, args, prefetch=False):
    binary = stage / "obj/Vtb"
    if binary.exists() and (not prefetch or binary.with_suffix(".optimized").exists()):
        return binary
    print(f"compile {name}", flush=True)
    # Prefetch uses a separate output directory. Publish only the completed
    # executable so the workload campaign cannot see a half-linked binary.
    obj = "obj-prefetch" if prefetch else "obj"
    command([VERILATOR, "-j", str(args.compile_jobs), "-Wno-fatal", "--cc", "--binary",
             "--build", "--Mdir", obj, "--trace", "--trace-depth", "2", "--trace-underscore",
             "-DFUNCTIONAL", "-DUNIT_DELAY", "-MAKEFLAGS", "OPT_FAST=-O1 OPT_SLOW=-O0",
             "netlist.v", *t["tb sources"].split(), *tech["sim"], "scripts/verilator.vlt",
             "--top-module", t["tb top"]], stage, {}, stage / f"compile-{obj}.log")
    if prefetch:
        binary.parent.mkdir(exist_ok=True)
        (stage / obj / "Vtb").replace(binary)
        shutil.rmtree(stage / obj)
    binary.with_suffix(".optimized").touch()
    return binary


def simulate(t, tech, name, stage, result, staenv, args):
    binary = compile_model(t, tech, name, stage, args)
    for workload in SUITE:
        if (result / f"{workload}.power.rpt").exists():
            continue
        print(f"simulate {name} {workload}", flush=True)
        hexfile = args.hex_dir / f"{workload}.hex"
        vcd = stage / f"{workload}.vcd.gz"
        simlog = result / f"{workload}.sim.log"
        # OpenSTA reopens the waveform. Store the losslessly compressed VCD
        # while Verilator writes to a local named pipe.
        with tempfile.TemporaryDirectory(dir="/tmp") as tmp:
            fifo = Path(tmp) / "waves.vcd"
            os.mkfifo(fifo)
            with vcd.open("wb") as out:
                zipper = subprocess.Popen(["sh", "-c", 'exec gzip -1 < "$1"', "gzip-vcd", str(fifo)], stdout=out)
                try:
                    command([binary, f"+hex={hexfile}", f"+vcd={fifo}", "+max_cycles=200000"], stage, {}, simlog)
                    if "TEST_RESULT PASS cycles=" not in simlog.read_text():
                        raise RuntimeError(f"Simulation failure: {simlog}")
                    if zipper.wait(timeout=60) != 0:
                        raise RuntimeError(f"VCD compression failed at {stage}")
                finally:
                    if zipper.poll() is None:
                        zipper.terminate()
                        zipper.wait()
        powerlog = stage / f"{workload}.power.log"
        power = stage / f"{workload}.power.rpt"
        command([STA, "-no_splash", "-exit", "scripts/opensta-power.tcl"], stage,
                {**staenv, "STA_POWER_TYPE":"1", "STA_VCD_FILENAME":str(vcd), "STA_POWER_REPORT_NAME":power.name},
                powerlog)
        log = powerlog.read_text()
        if "Error:" in log or "VCD activity normalized" not in log:
            raise RuntimeError(f"VCD power annotation failed: {powerlog}")
        compress(powerlog, result / f"{workload}.power.log.gz")
        if "100.0%" not in power.read_text():
            raise ValueError(f"Incomplete workload power report at {stage}")
        save_report(power, result / power.name)
        vcd.unlink()
    # Keep the linked executable and release regenerable compiler products.
    for item in binary.parent.iterdir():
        if item.is_file() and item not in (binary, binary.with_suffix(".optimized")):
            item.unlink()
    print(f"finished {name}", flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--scratch", type=Path, required=True)
    p.add_argument("--results", type=Path, default=ROOT / "results")
    p.add_argument("--hex-dir", type=Path, default=ROOT / "build/software")
    p.add_argument("--jobs", type=int, default=3)
    p.add_argument("--compile-jobs", type=int, default=2)
    p.add_argument("--static-only", action="store_true")
    p.add_argument("--compile-only", action="store_true", help="Precompile existing synthesized netlists and skip workloads")
    p.add_argument("--sizes", nargs="+", type=int, choices=[256, 512, 1024, 2048], default=[256, 512, 1024, 2048])
    p.add_argument("--libs", nargs="+", choices=["asap7", "nan45", "sky130"], default=["asap7", "nan45", "sky130"])
    p.add_argument("--arch", nargs="+", choices=list(ARCH), default=list(ARCH))
    p.add_argument("--scopes", nargs="+", choices=["cpu", "soc"], default=["cpu", "soc"])
    args = p.parse_args()
    for attr in ("scratch", "results", "hex_dir"):
        setattr(args, attr, getattr(args, attr).resolve())
    args.scratch.mkdir(parents=True, exist_ok=True, mode=0o700)
    scratch_tmp = args.scratch / "tmp"
    scratch_tmp.mkdir(exist_ok=True)
    os.environ["TMPDIR"] = str(scratch_tmp)
    specs = [(size, lib, scope, arch) for size in args.sizes for lib in args.libs
             for scope in args.scopes if scope == "soc" or (size, lib) == (256, "asap7") for arch in args.arch]
    failures = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(config_job, spec, args):spec for spec in specs}
        for f in as_completed(futures):
            try:
                f.result()
            except Exception:
                traceback.print_exc()
                failures.append(futures[f])
    if failures:
        sys.exit(f"Failed: {failures}")


if __name__ == "__main__":
    main()
