"""Count executed instructions and control transfers at the single-cycle instruction port."""
import csv
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import configure_cpu_build


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True, stderr=subprocess.STDOUT)


def main():
    cfg = configure_cpu_build()["rv32i-single-cycle-cpu"]
    with tempfile.TemporaryDirectory(prefix="cs505-count-") as tmp:
        tmp = Path(tmp)
        images = [tmp / "software" / name for name in cfg["sim args"]]
        run("make", "-s", f"BASE_OUTDIR={tmp}", *images)
        bench = (ROOT / cfg["tb sources"]).read_text()
        anchor = "// Match the SoC bench: count this active edge before checking results."
        assert bench.count(anchor) == 1
        bench = bench.replace(anchor, '''if (reset_ni && mmu_o_cpu_imem_valid)
            $display("FETCH %08h %08h", cpu_o_imem_addr, mmu_o_cpu_imem_data);
        ''' + anchor)
        monitor = tmp / "trace_tb.v"
        monitor.write_text(bench)
        exe = tmp / "count.vvp"
        run("iverilog", "-g2012", "-s", "tb", "-o", exe, *cfg["sources"].split(), monitor)
        rows = []
        for image in images:
            log = run("vvp", exe, f"+hex={image}", "+max_cycles=200000")
            passed = re.search(r"^TEST_RESULT PASS cycles=(\d+)$", log, re.M)
            trace = [(int(pc, 16), int(inst, 16)) for pc, inst in
                     re.findall(r"^FETCH ([\da-fA-F]{8}) ([\da-fA-F]{8})$", log, re.M)]
            if not passed or len(trace) != int(passed[1]) or trace[-1][1] != 0x00100073:
                raise RuntimeError(f"Invalid trace for {image.stem}: {log[-800:]}")
            ops = [inst & 0x7f for _, inst in trace]
            taken = sum(inst & 0x7f == 0x63 and next_pc != pc + 4 for
                        (pc, inst), (next_pc, _) in zip(trace, trace[1:]))
            rows.append((image.stem, len(trace), ops.count(0x63), taken,
                         ops.count(0x6f) + ops.count(0x67), ops.count(0x03), ops.count(0x23),
                         len(image.read_text().splitlines()) * 4))
    output = ROOT / "results/instructions.csv"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(("workload", "instructions", "branches", "taken_branches", "jumps",
                         "loads", "stores", "image_bytes"))
        writer.writerows(rows)


if __name__ == "__main__":
    main()
