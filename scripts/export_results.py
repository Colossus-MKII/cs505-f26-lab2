"""Audit all raw reports against RTL and export the complete measurement matrix."""
import argparse
import csv
import gzip
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "results"


def records(filename):
    with (ROOT / filename).open() as f:
        return list(csv.DictReader(f))


def write(filename, rows):
    with (ROOT / filename).open("w", newline="") as f:
        out = csv.DictWriter(f, fieldnames=list(rows[0]))
        out.writeheader()
        out.writerows(rows)


def total_watts(path):
    data = path.read_text()
    assert "Power (Watts)" in data, path
    w = re.search(r"^Total\s+(.+)$", data, re.M).group(1).split()
    internal, switching, leakage, total = map(float, w[:4])
    assert total > 0 and math.isclose(internal + switching + leakage, total, rel_tol=2e-6), path
    return total


def main():
    code = {r["workload"]: int(r["instructions"]) for r in records("instructions.csv")}
    reference = {(row["design"], row["workload"]): int(row["cycles"])
                 for row in records("rtl_cycles.csv") if row["status"] == "PASS"}
    assert len(code) == 11 and len(reference) == 66
    designs, workloads = [], []
    for size in (256, 512, 1024, 2048):
        for lib, node in (("asap7", 7), ("nan45", 45), ("sky130", 130)):
            scopes = ("cpu", "soc") if (size, node) == (256, 7) else ("soc",)
            for scope in scopes:
                for arch, fullname in (("single", "single-cycle"), ("multi", "multi-cycle"),
                                       ("pipe", "three-stage")):
                    p = ROOT / str(size) / lib / f"{scope}-{arch}"
                    with gzip.open(p / "synthesis.log.gz", "rt") as f:
                        areas = [float(line.rsplit(":", 1)[1]) for line in f if "Chip area for module" in line]
                    with gzip.open(p / "paths.rpt.gz", "rt") as f:
                        paths = f.read()
                    period_native = float((p / "period.rpt").read_text())
                    worst = float(re.search(r"([-\d.]+)\s+slack \(VIOLATED\)", paths)[1])
                    assert math.isclose(-worst, period_native, rel_tol=1e-5), p
                    unit = re.search(r"time\s+1(ps|ns)", (p / "units.log").read_text())[1]
                    assert (unit == "ps") == (lib == "asap7"), p
                    period = period_native * {"ps": 1e-12, "ns": 1e-9}[unit]
                    design = dict(technology=lib, node_nm=node, scope=scope, design=fullname, ram_bytes=size)
                    designs.append(dict(**design, area_um2=areas[-1], period_s=period, fmax_hz=1/period,
                                        statistical_w=total_watts(p / "statistical.rpt")))
                    ref_name = "rv32i-" + fullname + ("-single-bus" if (scope, arch) == ("cpu", "multi") else "") + "-" + scope
                    for name, count in code.items():
                        sim = (p / f"{name}.sim.log").read_text()
                        passed = re.findall(r"^TEST_RESULT PASS cycles=(\d+)\s*$", sim, re.M)
                        assert len(passed) == 1 and "TEST_RESULT FAIL" not in sim, (p, name)
                        cycles = int(passed[0])
                        assert reference[ref_name, name] == cycles, (p, name, cycles)
                        with gzip.open(p / f"{name}.power.log.gz", "rt") as f:
                            activity = f.read()
                        assert "Error:" not in activity and "VCD activity normalized" in activity, (p, name)
                        pins = int(re.search(r"Annotated (\d+) pin activities", activity)[1])
                        assert pins > 0, (p, name)
                        power = total_watts(p / f"{name}.power.rpt")
                        time = cycles * period
                        energy = power * time
                        workloads.append(dict(**design, workload=name, status="PASS", instructions=count,
                                              cycles=cycles, time_s=time, vcd_w=power, ipc=count/cycles,
                                              energy_j=energy, edp_js=energy*time, annotated_pins=pins))
    assert (len(designs), len(workloads)) == (39, 429)
    write("designs.csv", designs)
    write("workloads.csv", workloads)
    print(f"Verified {len(designs)} designs and {len(workloads)} passing gate-level measurements.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--progress", action="store_true", help="summarize available reports")
    if parser.parse_args().progress:
        print("RAM (B)   static   measured   total")
        for size, expected in ((256,132), (512,99), (1024,99), (2048,99)):
            root = ROOT / str(size)
            static = len(list(root.glob("*/*/statistical.rpt")))
            complete = len(list(root.glob("*/*/*.power.rpt")))
            print(f"{size:7} {static:8} {complete:10} {expected:7}")
    else:
        main()
