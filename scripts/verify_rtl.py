"""Run all workloads on the source RTL using Icarus and retain testbench cycle counts."""
import csv
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import configure_cpu_build


def run(args, cwd):
    completed = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, timeout=120)
    if completed.returncode:
        raise RuntimeError(f"{args[0]} exited {completed.returncode}: {completed.stdout[-1200:]}")
    return completed.stdout


def main():
    targets = configure_cpu_build()
    images = list(next(iter(targets.values()))["sim args"])
    results = []
    with tempfile.TemporaryDirectory(prefix=".rtl-check-", dir=ROOT) as scratch:
        scratch = Path(scratch)
        paths = [scratch / "software" / image for image in images]
        run(["make", "-s", f"BASE_OUTDIR={scratch}", *paths], ROOT)
        shutil.copytree(ROOT / "src", scratch / "src")
        config = scratch / "src/rv32i-memory/config.vh"
        template = config.read_text()
        for size in (256, 512, 1024, 2048):
            updated, matches = re.subn(r"(RAM_SIZE_BYTES\s*=\s*)\d+;",
                                       rf"\g<1>{size};", template)
            if matches != 1:
                raise ValueError("Expected one RAM capacity in config.vh")
            config.write_text(updated)
            for design, cfg in targets.items():
                if size != 256 and design.endswith("-cpu"):
                    continue
                exe = scratch / "bench.vvp"
                run(["iverilog", "-g2012", "-s", "tb", "-o", exe,
                     *cfg["sources"].split(), *cfg["tb sources"].split()], scratch)
                for path in paths:
                    log = run(["vvp", exe, f"+hex={path}", "+max_cycles=200000"], scratch)
                    match = re.search(r"^TEST_RESULT PASS cycles=(\d+)$", log, re.M)
                    if not match:
                        raise ValueError(f"{design}, {size} B, {path.stem}: {log[-1200:]}")
                    results.append((design, size, path.stem, "PASS", int(match[1])))
                print(f"{design} {size} B: {len(paths)} passed", flush=True)
    out = ROOT / "results"
    out.mkdir(exist_ok=True)
    for filename, rows in [
        ("rtl_cycles.csv", [r for r in results if r[1] == 256]),
        ("rtl_ram_cycles.csv", [r for r in results if r[0].endswith("-soc")]),
    ]:
        with (out / filename).open("w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(("design", "ram_bytes", "workload", "status", "cycles"))
            writer.writerows(rows)


if __name__ == "__main__":
    main()
