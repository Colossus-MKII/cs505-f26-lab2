#!/usr/bin/env python3
"""Typeset the lab report from retained Yosys, OpenSTA and simulator reports."""
import argparse
import csv
import gzip
import math
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results"
TECHS = {"asap7": ("ASAP7", 7, 1e-12), "nan45": ("Nangate45", 45, 1e-9),
         "sky130": ("Sky130 HD", 130, 1e-9)}
RAMS = (256, 512, 1024, 2048)
ARCH = {"single": "Single-cycle", "multi": "Multi-cycle", "pipe": "Three-stage"}
SCOPES = {"cpu": "CPU", "soc": "SoC"}
WORK = ("fib", "gcd", "popcount", "crc32", "histogram", "sieve127", "sqrt",
        "low-ilp", "high-ilp", "low-energy", "high-energy")
RATIOS = ("time", "ipc", "power", "energy", "edp")
NUMBER = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?"
MISSING = "---"


def read(path):
    if not path.is_file():
        return ""
    try:
        if path.suffix == ".gz":
            with gzip.open(path, "rt", errors="replace") as stream:
                return stream.read()
        return path.read_text(errors="replace")
    except (OSError, EOFError):
        return ""  # A report can be rendered while the sweep is still writing.


def read_area(path):
    # Synthesis progress logs are large. Scan lines incrementally.
    if not path.is_file():
        return None
    area = None
    try:
        with gzip.open(path, "rt", errors="replace") as lines:
            for line in lines:
                hit = re.search(r"Chip area for module .*?:\s*(" + NUMBER + ")", line)
                if hit:
                    area = float(hit[1])
    except (OSError, EOFError):
        return None
    return area


def power(path):
    for line in read(path).splitlines():
        if re.match(r"^\s*Total\s+", line):
            vals = re.findall(NUMBER, line)
            if len(vals) >= 4:
                return float(vals[3])
    return None


def divide(a, b):
    return a / b if a is not None and b else None


def product(a, b):
    return a * b if a is not None and b is not None else None


def positive_geomean(values):
    if not values or any(v is None or v <= 0 for v in values):
        return None
    return math.exp(statistics.mean(math.log(v) for v in values))


class Study:
    def __init__(self):
        self.instructions = {}
        path = RESULTS / "instructions.csv"
        if path.is_file():
            with path.open(newline="") as stream:
                self.instructions = {r["workload"]: r for r in csv.DictReader(stream)}
        self.rtl = {}
        for name in ("rtl_cycles.csv", "rtl_ram_cycles.csv"):
            path = RESULTS / name
            if path.is_file():
                with path.open(newline="") as stream:
                    for row in csv.DictReader(stream):
                        design = row["design"]
                        arch = "single" if "single-cycle" in design else "pipe" if "three-stage" in design else "multi"
                        scope = design.rsplit("-", 1)[1]
                        self.rtl[int(row["ram_bytes"]),scope,arch,row["workload"]] = (row["status"], int(row["cycles"]))
        self.circuit, self.run = {}, {}
        self.keys = [("asap7", 256, "cpu", a) for a in ARCH] + [
            (t, r, "soc", a) for t in TECHS for r in RAMS for a in ARCH]
        for t, r, s, a in self.keys:
            key = t, r, s, a
            folder = RESULTS / str(r) / t / (s + "-" + a)
            native = read(folder / "period.rpt").strip()
            period = float(native) * TECHS[t][2] if re.fullmatch(NUMBER, native) else None
            self.circuit[key] = {"area": read_area(folder / "synthesis.log.gz"),
                                 "period": period, "freq": divide(1, period),
                                 "stat": power(folder / "statistical.rpt")}
            for w in WORK:
                sim = read(folder / (w + ".sim.log"))
                hit = re.search(r"TEST_RESULT\s+(PASS|FAIL)\b([^\n]*)", sim)
                status = hit[1] if hit else "pending"
                cyc = re.search(r"cycles=(\d+)", hit[2]) if hit else None
                cycles = int(cyc[1]) if cyc else None
                if status == "FAIL" and re.search(r"(f0000007|f1000009|f2000007|f2000008|f300000a)", hit[2], re.I):
                    status = "timeout"
                gate = status
                rtl = self.rtl.get((r,s,a,w))
                if gate == "PASS" and rtl and (status, cycles) != rtl:
                    raise ValueError(f"Gate and RTL measurements disagree for {key} {w}")
                if status == "pending" and rtl:
                    status, cycles = rtl
                n = self.instructions.get(w, {}).get("instructions", "")
                n = int(n) if n else None
                watts = power(folder / (w + ".power.rpt")) if gate == "PASS" else None
                time = product(cycles, period) if status == "PASS" else None
                joules = product(watts, time)
                self.run[key, w] = {"status": status, "gate": gate, "cycles": cycles, "n": n,
                                    "time": time, "ipc": divide(n, cycles) if status == "PASS" else None,
                                    "power": watts, "energy": joules, "edp": product(joules, time)}

    def ratios(self, key, w):
        ref = self.run[(*key[:3], "single"), w]
        alt = self.run[key, w]
        if not (ref["status"] == alt["status"] == "PASS"):
            return dict.fromkeys(RATIOS)
        return {k: divide(alt[k], ref[k]) if k == "ipc" else divide(ref[k], alt[k]) for k in RATIOS}

    def aggregate(self, key):
        return {k: positive_geomean([self.ratios(key, w)[k] for w in WORK]) for k in RATIOS}

    def compare_circuits(self, key):
        ref = self.circuit[(*key[:3], "single")]
        return [divide(ref[field], self.circuit[key][field]) for field in ("area", "period", "stat")]


TEX = {
    "&": r"\&", "%": r"\%", "$": r"\$", "#": r"\#", "_": r"\_", "{": r"\{",
    "}": r"\}", "~": r"\textasciitilde{}", "^": r"\textasciicircum{}",
    "\\": r"\textbackslash{}", "µ": r"$\mu$", "μ": r"$\mu$", "²": r"$^2$",
    "×": r"$\times$", "−": "$-$", "≥": r"$\geq$", "≤": r"$\leq$",
    "→": r"$\rightarrow$", "≈": r"$\approx$", "Δ": r"$\Delta$", "–": "--",
    "—": "---", "’": "'", "‘": "`", "“": "``", "”": "''", "•": r"$\bullet$",
}


def escape(value):
    return "".join(TEX.get(c, c) for c in str(value))


def fmt(x, style=".4g"):
    if x is None:
        return MISSING
    return format(x, style)


def num(x):
    if x is None:
        return MISSING
    return str(x) if isinstance(x, int) else format(x, ".3e")


def table(headers, rows, cols=None, size="small", group_size=None):
    cols = cols or ("l" + "r" * (len(headers) - 1))
    head = " & ".join(headers) + r" \\"
    padding = "7.2pt" if group_size else "4.3pt"
    lines = ["{" + "\\" + size, r"\setlength{\tabcolsep}{" + padding + "}",
             r"\begin{longtable}{@{}" + cols + "@{}}", r"\toprule", head, r"\midrule",
             r"\endfirsthead", r"\toprule", head, r"\midrule", r"\endhead"]
    for i, row in enumerate(rows):
        if i and group_size and i % group_size == 0:
            lines.append(r"\addlinespace[4pt]")
        lines.append(" & ".join(str(x) for x in row) + r" \\")
    lines.extend([r"\bottomrule", r"\end{longtable}", "}"])
    return "\n".join(lines)


def paragraph(head, body):
    return r"\noindent\textbf{" + escape(head) + ".} " + escape(body) + "\n\n"


def section(title):
    return r"\section*{" + escape(title) + "}"


def smalltitle(title):
    return r"\subsection*{" + escape(title) + "}"


def extra_file(name):
    blocks = re.split(r"\n\s*\n", read(RESULTS / name).strip())
    return "\n\n".join(escape(" ".join(p.split())) for p in blocks if p)


def plot(study, outdir, node):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.ticker import MaxNLocator
    colors = {"single": "#3e5782", "multi": "#bd641c", "pipe": "#148272"}
    fig, axes = plt.subplots(1, 2, figsize=(7.15, 2.28))
    for ax, field, scale, ylabel in zip(axes, ("freq", "area"), (1e-6, 1e-3),
                                       ("Maximum frequency (MHz)", "Total SoC area (1,000 µm²)")):
        for a, marker in zip(ARCH, ("o", "s", "^")):
            values = [study.circuit[node, r, "soc", a][field] for r in RAMS]
            ys = [v * scale if v is not None else float("nan") for v in values]
            ax.plot(range(4), ys, label=ARCH[a], marker=marker, color=colors[a],
                    markersize=4, linewidth=1.7)
        ax.set_xticks(range(4), labels=["256", "512", "1,024", "2,048"])
        ax.set_xlabel("RAM capacity (B)", fontsize=9)
        ax.set_ylabel(ylabel, fontsize=8.5)
        ax.yaxis.set_major_locator(MaxNLocator(nbins=5))
        ax.tick_params(labelsize=8, length=3)
        ax.grid(axis="y", color="#d6dce2", linewidth=.65)
        ax.set_axisbelow(True)
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", ncol=3, frameon=False, fontsize=8.5)
    fig.subplots_adjust(left=.10, right=.98, top=.95, bottom=.35, wspace=.43)
    fig.savefig(outdir / (node + ".pdf"))
    plt.close(fig)


HEADER = r"""\documentclass[10pt,letterpaper]{article}
\usepackage[T1]{fontenc}
\usepackage[utf8]{inputenc}
\usepackage[margin=.75in,top=.76in,bottom=.78in]{geometry}
\usepackage{newtxtext,newtxmath,booktabs,longtable,array,graphicx,xcolor,fancyhdr}
\definecolor{ink}{HTML}{163E49}
\definecolor{slate}{HTML}{3B5960}
\usepackage{titlesec}
\titleformat{\section}{\Large\bfseries\color{ink}}{}{0pt}{}
\titleformat{\subsection}{\large\bfseries\color{ink}}{}{0pt}{}
\titlespacing*{\section}{0pt}{3pt}{7pt}
\titlespacing*{\subsection}{0pt}{9pt}{3pt}
\setlength{\parindent}{0pt}
\setlength{\parskip}{4pt}
\setlength{\LTleft}{0pt}
\setlength{\LTright}{\fill}
\setlength{\LTpre}{4pt}
\setlength{\LTpost}{5pt}
\renewcommand{\arraystretch}{1.06}
\pagestyle{fancy}\fancyhf{}
\lhead{\small\textcolor{slate}{CS 505 $\cdot$ Fall 2026}}
\rhead{\small\textcolor{slate}{Lab 2 $\cdot$ CPU benchmarking}}
\cfoot{\small\thepage}
\renewcommand{\headrulewidth}{.25pt}
\setlength{\headheight}{14pt}
\emergencystretch=1.5em
\begin{document}
"""

def intro(st):
    designs = sum(all(v is not None for v in d.values()) for d in st.circuit.values())
    passed = sum(v["gate"] == "PASS" for v in st.run.values())
    power_count = sum(v["power"] is not None for v in st.run.values())
    out = [r"{\Huge\bfseries\color{ink} CPU benchmarking}\par",
           r"{\large Three RV32I implementations across memory sizes and process technologies}\par",
           section("Experiment"),
           escape("Each implementation executes the same eleven linked programs. At 7 nm the CPU measurement models memory outside the design with immediate responses. The SoC adds address decoding and synthesized, asynchronously read RAM. The larger experiment varies this RAM from 256 B to 2,048 B in three cell libraries. All designs run at their own static-timing limit."),
           paragraph("Measurement coverage",
                     f"{designs}/39 designs have area, timing and statistical power. "
                     f"{passed}/429 gate-level workload tests passed and {power_count}/429 have workload power estimates. "
                     f"The independently simulated RTL passed {sum(v[0]=='PASS' for v in st.rtl.values())}/{len(st.rtl)} workload/configuration tests.")]
    if designs < 39 or power_count < 429:
        out.append(paragraph("Coverage", "A dash identifies a measurement or comparison still unavailable. "
                             "Time and IPC use measured RTL cycles whenever a gate-level simulation is pending. Workload power always requires gate-level activity. Every aggregate requires all eleven baseline/candidate pairs."))
    base_core = st.aggregate(("asap7",256,"cpu","pipe"))["time"]
    base_soc = st.aggregate(("asap7",256,"soc","pipe"))["time"]
    if base_core and base_soc:
        out.append(paragraph("Baseline comparison", f"At 7 nm and 256 B, the three-stage design delivers {base_core:.3f}× the single-cycle speed with ideal external memory and {base_soc:.3f}× with the memory included. The same instruction streams yield opposite design choices for suite latency."))
    out += [smalltitle("Four additional workloads"),
            table(["Workload", "Instructions", "Image (B)", "Stack frame (B)", "Loads", "Stores"],
                  [[w, *[st.instructions.get(w, {}).get(x, MISSING) for x in ("instructions", "image_bytes")],
                    "16" if w == "high-energy" else "0",
                    st.instructions.get(w, {}).get("loads", MISSING), st.instructions.get(w, {}).get("stores", MISSING)]
                   for w in WORK[-4:]]),
            paragraph("Low ILP", "Eight consecutive add-immediate instructions update the same register on each of 98 iterations. Each sum needs the previous sum. The final check verifies 784."),
            paragraph("High ILP", "The matched loop updates eight distinct registers on each of 98 iterations. The next iteration depends on values from the previous one, but the eight additions within an iteration can execute independently. Eight comparisons check that every register reaches 98."),
            paragraph("Low energy", "Eighteen identical add-immediate instructions repeatedly write zero back to the same register. Across 49 iterations, 882 instructions keep the operand, result, and most instruction bits constant. Fetch, clock distribution and loop control still switch. The program checks the accumulator."),
            paragraph("High energy", "Each iteration issues eight loads and eight stores. Complementary checkerboard words alternate across two aligned stack locations, switching data on the bus and at the storage cells. After 55 iterations, the program checks both final reads. The 16-byte frame touches eight bytes."),
            escape("The common entry code initializes the stack, calls main, writes the success value to MMIO and executes EBREAK. The images above include that code and the reserved stack. Each main returns 0 on success or 1 on a detected error. Loads and stores include the wrapper's final status store.")]
    return "\n\n".join(out)


def predictions():
    lines = [x.split("|") for x in read(ROOT / "predictions.txt").splitlines() if "|" in x][1:]
    out = [section("Predictions before measurement"), escape("These predictions were recorded before synthesis and simulation. Energy, power and overall latency refer to equal workload weight across the suite.")]
    rows = []
    for fields in lines:
        cells = [escape(fields[0].strip())]
        for field in fields[1:]:
            name, reason = field.strip().split(": ", 1)
            cells.append(r"\textbf{" + escape(name) + "}. " + escape(reason[:1].upper() + reason[1:]))
        rows.append(cells)
    out += [table(["Property", "CPU with ideal memory", "SoC with integrated RAM"], rows,
                  r">{\raggedright\arraybackslash}p{1.13in}>{\raggedright\arraybackslash}p{2.75in}>{\raggedright\arraybackslash}p{2.76in}", "small"), smalltitle("Measurement and normalization"),
            escape("Area is the mapped-cell sum from Yosys. OpenSTA determines the register and interface timing limits. Its native period is in ps for ASAP7 and ns for Nangate45 and Sky130 HD. The power reports explicitly label their total in watts. The statistical estimate assumes primary input activity of 0.2. The workload estimate uses gate-level signal transitions and the design's minimum period."),
            escape("Dynamic instruction counts include the complete wrapper and the terminal EBREAK. The testbench counts active clocks until it observes the expected exception and a successful MMIO result. Program loading and reset precede the execution window. IPC here is executed instructions divided by those clocks."),
            r"With clock period $T$, cycle count $C$, dynamic count $I$ and VCD power $P$, "
            r"$f_{\max}=1/T$, $t=CT$, $\mathrm{IPC}=I/C$, $E=Pt$ and $\mathrm{EDP}=Pt^2$. "
            r"Ratios compare each design with single-cycle at identical scope, process and memory size. "
            r"IPC ratios use candidate/baseline. The others use baseline/candidate, so values above one indicate improvement.",
            escape("Table 4 and the memory sweep use the geometric mean of the eleven positive per-workload ratios. Multiplicative factors combine through products. Reversing every comparison reciprocates the geometric mean, while an arithmetic mean of ratios lacks that symmetry. Absolute recommendations use the same workload weighting.")]
    return "\n\n".join(out)


def design_table(st):
    out = [section("Table 1. Microarchitectures"), escape("ASAP7 at 7 nm. CPU scope uses 256 B of external testbench memory and excludes its area. SoC scope includes 256 B of mapped RAM.")]
    keys = [("asap7", 256, s, a) for s in SCOPES for a in ARCH]
    rows = []
    for t, r, s, a in keys:
        d = st.circuit[t, r, s, a]
        rows.append([ARCH[a], SCOPES[s], "7", str(r), fmt(d["area"],".2f"),
                     num(d["period"]), num(d["freq"]), num(d["stat"])])
    out.append(table(["Architecture", "Scope", "nm", "RAM (B)", r"Area ($\mu$m$^2$)", "$T$ (s)", "$f$ (Hz)", "$P_{stat}$ (W)"], rows, "llrrrrrr"))
    out.append(smalltitle("Why the measured clock limits differ"))
    if all(st.circuit[k]["period"] and st.circuit[k]["area"] for k in keys):
        for a in ARCH:
            cpu, soc = (st.circuit["asap7",256,scope,a] for scope in SCOPES)
            out.append(paragraph(ARCH[a], f"Adding RAM changes the period from {cpu['period']*1e9:.3f} to {soc['period']*1e9:.3f} ns "
                                 f"and adds {soc['area']-cpu['area']:.1f} µm² of mapped cells."))
        out.append(escape("The CPU timing constraints set zero external delay on instruction and data ports. The isolated single-cycle core therefore has no combinational link between its outgoing instruction address and incoming instruction word, or between its data address and returning load value. The SoC closes both paths through mapped RAM and decode logic."))
        out.append(escape("At 7 nm, the isolated single-cycle critical path connects register-file byte lanes. The multi-cycle path connects controller-state registers. In the pipeline the path starts at the registered instruction, crosses operand selection and carry logic, and ends at the memory/writeback result register. Changing the stage boundaries leaves a long core path, which explains why the isolated pipeline misses its predicted clock advantage."))
        out.append(escape("Using one time-shared bus saves storage ports in the multi-cycle implementation. Its control loop and arithmetic still set a clock limit. Adding and remapping the SoC can change which gates and endpoints dominate the path."))
    return "\n\n".join(out)


def aggregate_baseline(st):
    keys = [("asap7", 256, s, a) for s in SCOPES for a in ("multi","pipe")]
    out = [section("Table 4. Aggregate benchmark results"),
            escape("The five workload columns are geometric means. The last three use individual synthesis and timing reports. Tables 2 and 3 give the underlying workload measurements and ratios.")]
    out.append(aggregate_table(st, [k for k in keys if k[-1] != "single"], True))
    return "\n\n".join(out)


def aggregate_table(st, keys, baseline=False):
    rows = []
    for k in keys:
        ratio = st.aggregate(k)
        rows.append([SCOPES[k[2]] if baseline else str(k[1]), ARCH[k[-1]],
                     *[fmt(ratio[x], ".3f") for x in RATIOS],
                     *[fmt(v, ".3f") for v in st.compare_circuits(k)]])
    return table(["Scope" if baseline else "B", "Design", "Speedup", "IPC", r"$P_{vcd}$",
                  "$E$", "EDP", "Area", "$T$", "$P_{stat}$"], rows, "llrrrrrrrr", "small")


def workload_table(st, s):
    out = [section("Table 2. Workloads | " + SCOPES[s]), escape("ASAP7, 7 nm, 256 B. All times, VCD power, energy and EDP use SI units. The design label applies to its following rows.")]
    if any(st.run[("asap7",256,s,a),w]["gate"] == "pending" for a in ARCH for w in WORK):
        out.append(escape("An RTL suffix identifies a source-RTL result. Other status entries refer to a mapped gate-level run."))
    rows = []
    for a in ARCH:
        for i, w in enumerate(WORK):
            v = st.run[("asap7", 256, s, a), w]
            rows.append([ARCH[a] if not i else "", w, v["status"] + ("/RTL" if v["gate"] == "pending" and v["status"] == "PASS" else ""), fmt(v["n"], "d"), fmt(v["cycles"], "d"),
                         num(v["time"]), num(v["power"]), fmt(v["ipc"],".3f"), num(v["energy"]), num(v["edp"])])
    out.append(table(["Design", "Workload", "Status", "$I$", "$C$", "$t$ (s)", "$P$ (W)", "IPC", "$E$ (J)", r"EDP (J$\cdot$s)"], rows, "lllrrrrrrr", "normalsize", len(WORK)))
    return "\n\n".join(out)


def normalized_table(st):
    out = [section("Table 3. Normalized comparison"), escape("ASAP7 at 7 nm and 256 B. Each workload uses the single-cycle result within its own scope as denominator for IPC and numerator for all other columns. Rows are grouped by scope and candidate.")]
    rows = []
    for s in SCOPES:
        for a in ("multi", "pipe"):
            for i,w in enumerate(WORK):
                v = st.ratios(("asap7", 256, s, a), w)
                rows.append([SCOPES[s] if not i else "", ARCH[a] if not i else "", w,
                             *[fmt(v[x], ".3f") for x in RATIOS]])
    out.append(table(["Scope", "Design", "Workload", "Speedup", "IPC ratio", "$P$ reduction", "$E$ reduction", "EDP gain"], rows, "lllrrrrr", "footnotesize"))
    return "\n\n".join(out)


def measurements(st, s):
    def metric(a, m):
        k = ("asap7", 256, s, a)
        if m in ("area", "period"):
            return st.circuit[k][m]
        if m in ("low-ilp", "high-ilp"):
            return st.run[k, m]["time"]
        return positive_geomean([st.run[k, w][m] for w in WORK])
    return {m: {a: metric(a, m) for a in ARCH} for m in
            ("area", "cycles", "period", "low-ilp", "high-ilp", "time", "energy", "power")}


def winner(values):
    if any(v is None for v in values.values()):
        return None
    return min(values, key=values.get)


def findings(st):
    out = [section("7 nm findings"), smalltitle("Prediction check")]
    predicted = {"cpu": ["multi","single","multi","pipe","pipe","pipe","single","multi"],
                 "soc": ["multi","single","multi","pipe","pipe","pipe","pipe","multi"]}
    measured = {s: measurements(st, s) for s in SCOPES}
    metrics = list(measured["cpu"])
    names = ["Area", "Fewest cycles", "Period", "Low-ILP time", "High-ILP time", "Suite time", "Suite energy", "Suite power"]
    rows = []
    for i,(m,label) in enumerate(zip(metrics, names)):
        row = [label]
        for s in SCOPES:
            win = winner(measured[s][m])
            row.extend([ARCH[predicted[s][i]], ARCH[win] if win else MISSING])
        rows.append(row)
    out.append(table(["Property", "CPU prediction", "CPU result", "SoC prediction", "SoC result"], rows, "lllll"))
    for s in SCOPES:
        m = measured[s]
        if all(winner(m[x]) for x in ("time","period","cycles")):
            fastest = winner(m["time"])
            p = m["period"]["pipe"] / m["period"]["single"]
            c = m["cycles"]["pipe"] / m["cycles"]["single"]
            t = m["time"]["single"] / m["time"][fastest]
            explanation = (f"The three-stage design takes {c:.3f}× the single-cycle clocks at {p:.3f}× the period. "
                           f"{ARCH[fastest]} consequently has the shortest geometric-mean time, {t:.3f}× the baseline speed. "
                           f"The multi-cycle design takes {m['cycles']['multi']/m['cycles']['single']:.2f}× as many clocks as single-cycle because it sequences fetch, decode and execution over its shared bus.")
            if winner(m["power"]) and winner(m["energy"]):
                explanation += (f" {ARCH[winner(m['power'])]} draws the least average power across programs. "
                                f"Multiplying by time gives the lowest energy to {ARCH[winner(m['energy'])]}.")
            if s == "soc" and winner(m["energy"]):
                explanation += (f" Three-stage draws {m['power']['pipe']/m['power']['single']:.2f}× single-cycle power. "
                                f"Its shorter runtime leaves {m['energy']['pipe']/m['energy']['single']:.2f}× the energy. "
                                f"The single-ported multi-cycle SoC clocks RAM at {m['period']['single']/m['period']['multi']:.2f}× the single-cycle frequency, so sharing one port alone did not minimize watts.")
            out.append(paragraph(SCOPES[s], explanation))
    out += [smalltitle("What the longest SoC timing paths compute"),
            extra_file("critical_paths_256.txt") or escape("Path identification awaits interpretation of the SoC timing reports.")]
    return "\n\n".join(out)


def pipeline_findings(st):
    out = [section("Pipeline behavior and application choices")]
    measured = {s: measurements(st, s) for s in SCOPES}
    for s in SCOPES:
        k = ("asap7", 256, s, "pipe")
        ratios = {w: st.ratios(k, w)["time"] for w in WORK}
        if all(v is not None for v in ratios.values()):
            lead, lag = max(ratios,key=ratios.get), min(ratios,key=ratios.get)
            def redirects(w):
                v = st.instructions.get(w, {})
                return int(v.get("taken_branches", 0)) + int(v.get("jumps",0))
            text = (f"{lead} gets the largest pipelining speedup ({ratios[lead]:.3f}×) and {lag} the smallest ({ratios[lag]:.3f}×). "
                    f"The instruction trace records {redirects(lead)} control redirects in {st.run[k,lead]['n']} instructions for {lead}, compared with {redirects(lag)} in {st.run[k,lag]['n']} for {lag}. ")
            vs = [(1 - (st.run[k,w]["n"] - 1) / st.run[k,w]["cycles"]) for w in WORK]
            summed = 1 - sum(st.run[k,w]["n"]-1 for w in WORK) / sum(st.run[k,w]["cycles"] for w in WORK)
            if ratios[lead] < 1:
                text += "All programs take longer on this pipeline than on the single-cycle core. "
            text += (f"Counting all program clocks together, {100*summed:.2f}% have no retirement. "
                     f"The per-program range is {100*min(vs):.2f}% to {100*max(vs):.2f}%.")
            out.append(paragraph(SCOPES[s] + " pipeline", text))
    k = ("asap7",256,"soc","pipe")
    ex = st.run[k,"low-ilp"], st.run[k,"high-ilp"]
    if all(v["cycles"] and v["n"] for v in ex):
        out.append(escape(f"The dependent and independent addition workloads use {ex[0]['cycles']} and {ex[1]['cycles']} pipeline clocks. "
                          f"Subtracting their {ex[0]['n']} and {ex[1]['n']} executed instructions gives {ex[0]['cycles']-ex[0]['n']} and {ex[1]['cycles']-ex[1]['n']} excess clocks. "
                          "Their matched loop counts isolate the effect of dependence from redirect overhead."))
    out += [escape("The CPU can retire at most one instruction per clock. With I counting the terminating trap, (I − 1) instructions retire on a successful run. The no-retirement fraction is 1 − (I − 1)/C. A taken branch, JAL or JALR resolves in EX and suppresses fetch for the redirect. Pipeline fill, halt detection and short runtimes magnify fixed overhead. The MEM/WB stage forwards an ALU result or a valid load value directly to either EX operand. An adjacent dependent add can therefore progress every cycle with immediate memory. Independent arithmetic offers more exploitable parallelism, but this scalar issue width caps throughput."),
            smalltitle("CPU and SoC ranking")]
    for m,label in (("time","Latency"),("power","Power"),("energy","Energy"),("area","Area")):
        if all(winner(measured[s][m]) for s in SCOPES):
            def ordering(s):
                return " < ".join(ARCH[a] for a in sorted(ARCH, key=measured[s][m].get))
            changed = ordering("cpu") != ordering("soc")
            out.append(paragraph(label, f"CPU, in ascending order is {ordering('cpu')}. SoC order is {ordering('soc')}. "
                                 + ("The ordering changes." if changed else "The ordering persists.")))
    out.append(escape("The SoC includes the address decoder, physical read multiplexers, memory cells and their switching. Single-cycle and three-stage have separate instruction and data access paths, while multi-cycle shares one port."
                      + " SoC timing and energy describe a complete processor-memory implementation more closely. A CPU-only comparison isolates core costs."))
    return "\n\n".join(out)


def power_findings(st):
    out = [section("Power estimation and design selection"),
           escape("The following ranges compare statistical power with the workload estimates at each design's own minimum period. The ratios use statistical/VCD power. A ratio of one is an exact match.")]
    rows = []
    for s in SCOPES:
        for a in ARCH:
            key = ("asap7", 256, s, a)
            stat = st.circuit[key]["stat"]
            rs = [divide(stat, st.run[key,w]["power"]) for w in WORK]
            done = all(v is not None for v in rs)
            rows.append([SCOPES[s], ARCH[a], fmt(stat), fmt(min(rs)) if done else MISSING,
                         fmt(positive_geomean(rs)), fmt(max(rs)) if done else MISSING])
    out.append(table(["Scope","Design","Statistical W","Min ratio","Geo. mean","Max ratio"],rows,"llrrrr"))
    all_factors=[divide(st.circuit[k]["stat"],st.run[k,w]["power"]) for k in st.keys if k[:2]==("asap7",256) for w in WORK]
    observed = [x for x in all_factors if x is not None]
    if observed:
        out.append(escape(f"The statistical estimate exceeds VCD power in {sum(v>1 for v in observed)} of {len(observed)} measured cases. "
                          f"Across those observations the largest overestimate is {max(0,max(observed)-1)*100:.1f}% and the largest underestimate is {max(0,1-min(observed))*100:.1f}%."))
    out.append(escape("The fixed primary-input activity ignores instruction mix, stable operands, correlated register values and the frequency of memory writes. The trace exposes those transitions. Clocked storage and leakage draw power on quiet workloads as well. These cell-model estimates use synthesized logic and ideal clocks. They do not include extracted routing or a laid-out clock tree."))
    out.append(smalltitle("Selecting a design at 7 nm with 256 B"))
    vals = measurements(st,"soc")
    for m,label,unit in (("time","Latency-sensitive","s"),("energy","Battery-powered","J"),("area","Area-constrained","µm²")):
        a = winner(vals[m])
        if a:
            runner = sorted(ARCH,key=vals[m].get)[1]
            advantage = 100 * (1 - vals[m][a] / vals[m][runner])
            out.append(paragraph(label, f"Choose {ARCH[a]} at {fmt(vals[m][a])} {unit}. "
                                 f"This is {advantage:.1f}% below the next best option, {ARCH[runner]} at {fmt(vals[m][runner])} {unit}."))
    return "\n\n".join(out)

def sweep_panel(st,node,index):
    tech,nm,_ = TECHS[node]
    out = [section(f"Memory sweep | {tech} ({nm} nm)"),
           smalltitle(f"Figure {index}. Frequency and mapped SoC area"),
           r"\includegraphics[width=.99\linewidth]{"+node+".pdf}",
           escape("Each point is a separate synthesis and timing run. The area panel gives estimated total SoC area, including the CPU, RAM, address decoding and host interface. The log-spaced capacity axis advances by one doubling per step."),
           smalltitle("Matched aggregate benchmark results"),
           escape("Speedup, IPC, workload power, energy and EDP are geometric means across eleven programs. The last three columns compare mapped circuit properties. A factor of one is the single-cycle baseline at the same RAM capacity and node."),
           aggregate_table(st,[(node,r,"soc",a) for r in RAMS for a in ("multi","pipe")]),
           smalltitle("How RAM changes the critical period and area")]
    rows = []
    for a in ARCH:
        ds = [st.circuit[node,r,"soc",a] for r in RAMS]
        periods = [product(d["period"],1e9) for d in ds]
        area_factors = [divide(ds[i+1]["area"],ds[i]["area"]) for i in range(3)]
        rows.append([ARCH[a], *[fmt(x,".3f") for x in periods],
                     *[fmt(x,".3f") for x in area_factors]])
    out += [escape("The first four numeric columns are periods in ns. Each of the final three columns is the ratio of total area after one doubling to the preceding area."),
            table(["Design","256 B","512 B","1,024 B","2,048 B","512/256","1,024/512","2,048/1,024"],rows)]
    return "\n\n".join(out)


def sweep_discussion(st):
    out=[section("Interpreting the memory sweep"),smalltitle("Frequency spread and timing sensitivity")]
    def spread(k):
        vals=[st.circuit[(*k,a)]["freq"] for a in ARCH]
        return max(vals)/min(vals) if all(vals) else None
    cpu = spread(("asap7",256,"cpu"))
    soc = spread(("asap7",256,"soc"))
    if cpu and soc:
        out.append(escape(f"At 7 nm and 256 B, the fastest/slowest clock-frequency ratio changes from {cpu:.3f} across cores in isolation to {soc:.3f} across complete SoCs. Only ASAP7 has a measured CPU-only control."))
    for node in TECHS:
        name=TECHS[node][0]
        changes={a:divide(st.circuit[node,2048,"soc",a]["period"],st.circuit[node,256,"soc",a]["period"]) for a in ARCH}
        if all(changes.values()):
            a=max(changes,key=changes.get)
            absolute = {a: (st.circuit[node,2048,"soc",a]["period"] - st.circuit[node,256,"soc",a]["period"]) * 1e9 for a in ARCH}
            abs_arch = max(absolute,key=absolute.get)
            out.append(paragraph(name, f"{ARCH[a]} has the largest fractional period increase from 256 B to 2,048 B "
                                 f"({100*(changes[a]-1):+.1f}%). Single-cycle, multi-cycle and three-stage changes are "
                                 + ", ".join(f"{100*(v-1):+.1f}%" for v in changes.values())
                                 + f", respectively. The largest absolute increase is {absolute[abs_arch]:.3f} ns for {ARCH[abs_arch]}. The largest/smallest frequency ratio goes from {spread((node,256,'soc')):.3f} to {spread((node,2048,'soc')):.3f}."))
    if extra_file("critical_paths_sweep.txt"):
        out.append(extra_file("critical_paths_sweep.txt"))
    out.append(smalltitle("Cycles, area and aggregate ranking"))
    diffs=[]
    for a in ARCH:
        for w in WORK:
            values=[st.run[(t,r,"soc",a),w]["cycles"] for t in TECHS for r in RAMS]
            if all(values) and all(st.run[(t,r,"soc",a),w]["gate"] == "PASS" for t in TECHS for r in RAMS):
                diffs.append(max(values)-min(values))
    rtl_spreads = []
    for a in ARCH:
        for w in WORK:
            vs = [st.rtl.get((ram,"soc",a,w)) for ram in RAMS]
            if all(v and v[0] == "PASS" for v in vs):
                counts = [v[1] for v in vs]
                rtl_spreads.append(max(counts)-min(counts))
    if rtl_spreads:
        out.append(escape(f"Source RTL tests isolate the effect of RAM size. The largest cycle-count spread across four capacities is {max(rtl_spreads)} in the {len(rtl_spreads)} matched architecture/workload combinations."))
    if diffs:
        out.append(escape(f"Across {len(diffs)} workload/architecture combinations with gate-level observations at all 12 node/capacity points, "
                          f"the largest within-combination change is {max(diffs)} cycle(s). "
                          + "For example, high-energy takes "
                          + ", ".join(f"{st.run[('asap7',256,'soc',a),'high-energy']['cycles']:,}" for a in ARCH if st.run[('asap7',256,'soc',a),'high-energy']['cycles'] is not None)
                          + " cycles at 7 nm/256 B in single-cycle, multi-cycle and three-stage order. "
                          + "The programs and control sequences remain the same, the address map keeps every program inside RAM, and the modeled RAM responds combinationally. Technology changes path delays in seconds."))
    changes = [divide(st.circuit[t,r*2,"soc",a]["area"],st.circuit[t,r,"soc",a]["area"])
               for t in TECHS for r in RAMS[:-1] for a in ARCH]
    if all(changes):
        out.append(escape(f"A doubling multiplies total SoC area by {min(changes):.3f} to {max(changes):.3f} across the 27 cases. "
                          "The CPU and much of the interface are fixed costs. Added memory introduces storage bits, read selection and write decode. The mapped gates also depend on port count and the available library cells."))
    rankings = {}
    for t in TECHS:
        for r in RAMS:
            vals={a:st.aggregate((t,r,"soc",a))["time"] for a in ARCH}
            if all(vals.values()):
                ranking=tuple(sorted(ARCH,key=vals.get,reverse=True))
                rankings.setdefault(ranking,[]).append(f"{TECHS[t][0]} {r} B")
    if rankings:
        for order,keys in rankings.items():
            where=f"all {len(keys)} measured configurations" if len(rankings)==1 else ", ".join(keys)
            out.append(escape("In " + where + ", execution time ranks " + ", ".join(ARCH[a] for a in order)
                              + " from fastest to slowest. The speedups in the node-specific tables include both the period benefit and the measured cycle penalty."))
    return "\n\n".join(out)


def energy_values(st,k,field):
    def per(w):
        v=st.run[k,w]
        return divide(v["energy"],v[field])
    background = positive_geomean([per(w) for w in WORK if w not in ("low-energy","high-energy")])
    return tuple(per(w) for w in ("low-energy","high-energy")) + tuple(
        divide(per(w),background) for w in ("low-energy","high-energy"))


def energy_analysis(st):
    out=[section("Energy per instruction and per cycle"),
         escape("The four ratios in each row divide each energy workload by the geometric mean of the other nine programs on that same SoC. The first pair uses J/instruction and the second J/cycle. The last two columns give absolute energy per executed instruction in pJ. A ratio below one indicates less energy than the reference.")]
    rows=[]
    for node in TECHS:
        for ram in RAMS:
            for a in ARCH:
                k=node,ram,"soc",a
                ei=energy_values(st,k,"n")
                ec=energy_values(st,k,"cycles")
                rows.append([TECHS[node][0] if a=="single" and ram==256 else "",
                             str(ram) if a=="single" else "", ARCH[a], *[fmt(x,".3f") for x in (*ei[2:],*ec[2:])],
                             *[fmt(product(x,1e12),".3g") for x in ei[:2]]])
    out.append(table(["Library","B","Design","Low $E/I$","High $E/I$","Low $E/C$","High $E/C$","Low pJ/I","High pJ/I"],rows,"lr lrrrrrr","footnotesize"))
    return "\n\n".join(out)


def energy_conclusion(st):
    out=[section("Switching activity and extrapolation")]
    keys=[k for k in st.keys if k[2]=="soc"]
    for field,label in (("n","Energy per instruction"),("cycles","Energy per cycle")):
        es=[energy_values(st,k,field) for k in keys]
        complete=[e for e in es if all(x is not None for x in e)]
        if complete:
            quiet=sum(e[2]<1 for e in complete)
            busy=sum(e[3]>1 for e in complete)
            hiquiet=sum(e[1]>e[0] for e in complete)
            ranks = []
            for k in keys:
                levels = {w:divide(st.run[k,w]["energy"],st.run[k,w][field]) for w in WORK}
                if all(levels.values()):
                    ranks.append(sorted(WORK,key=levels.get))
            lowest = sum(r[0]=="low-energy" for r in ranks)
            highest = sum(r[-1]=="high-energy" for r in ranks)
            out.append(paragraph(label, f"Low-energy falls below the other workloads' geometric mean in {quiet}/{len(complete)} configurations. "
                                 f"High-energy exceeds it in {busy}/{len(complete)} and exceeds low-energy in {hiquiet}/{len(complete)}. Low-energy is the minimum in {lowest} cases and high-energy the maximum in {highest}. "
                                 f"Low-energy/reference ranges from {min(e[2] for e in complete):.3f} to {max(e[2] for e in complete):.3f}, "
                                 f"and high-energy/reference from {min(e[3] for e in complete):.3f} to {max(e[3] for e in complete):.3f}."))
    out.append(escape("Energy and power answer different questions. A short high-power run may use less total energy than a long low-power run. At fixed frequency, P = (E/C)f, so workload power rankings coincide with energy per cycle within a given design. "
                      "To change average power, sustain different rates of switching per clock. Repeating an instruction with constant data limits ALU and register transitions, while alternating complementary memory data drives activity in the memory ports and data path. Clocks, fetch and leakage contribute a floor."))
    for t in TECHS:
        parts=[]
        for a in ARCH:
            def gap(r):
                e=energy_values(st,(t,r,"soc",a),"cycles")
                return divide(e[1],e[0])
            if gap(256) and gap(2048):
                parts.append(f"{ARCH[a]} {gap(256):.2f} to {gap(2048):.2f}")
        if parts:
            out.append(paragraph(TECHS[t][0], "High/low energy-per-cycle ratios from 256 B to 2,048 B are " + ", ".join(parts) + "."))
    ref = [energy_values(st,(t,256,"soc","single"),"cycles")[3] for t in TECHS]
    if all(ref):
        out.append(escape("At 256 B, high-energy/reference energy per cycle on the single-cycle SoC is "
                          + ", ".join(f"{v:.3f} at {TECHS[t][1]} nm" for t,v in zip(TECHS,ref))
                          + ". The same instruction sequence falls on different sides of the reference across libraries."))
    out += [escape("The absolute pJ/instruction columns expose cross-library energy differences. More storage changes the number of clocked cells and read-select gates. Different cell capacitances, delays and leakage alter the balance between this common cost and workload-specific switching."),
            smalltitle("Single-cycle period with 8 GiB of RAM"),
            r"Interpret 8 GB as 8 GiB ($2^{33}$ B). For each library, fit the four measured single-cycle SoC periods by least squares with $T=a+b\log_2(R/256\,\mathrm{B})$. A balanced multiplexer tree motivates the per-doubling term. The target is 25 doublings from 256 B, or 22 beyond the largest measured RAM."]
    rows=[]
    for t in TECHS:
        vals=[product(st.circuit[t,r,"soc","single"]["period"],1e9) for r in RAMS]
        if all(vals):
            avg=statistics.mean(vals)
            slope=sum((i-1.5)*(p-avg) for i,p in enumerate(vals))/5
            intercept=avg-1.5*slope
            pred=intercept+25*slope
            fitted=[intercept+i*slope for i in range(4)]
            residual=max(abs(a-b) for a,b in zip(vals,fitted))
            centered = [r-statistics.mean(RAMS) for r in RAMS]
            per_byte = sum(x*(v-avg) for x,v in zip(centered,vals)) / sum(x*x for x in centered)
            predicted_linear = avg + (2**33-statistics.mean(RAMS))*per_byte
            residual_linear = max(abs(v-avg-x*per_byte) for v,x in zip(vals,centered))
            rows.append([TECHS[t][0],fmt(intercept,".3f"),fmt(slope,".3f"),fmt(residual,".3f"),fmt(pred,".2f"),
                         fmt(residual_linear,".3f"),fmt(predicted_linear*1e-6,".2f")])
    if rows:
        out.append(escape("The last two columns test sensitivity to persistent address fanout by fitting period linearly in bytes. The large divergence illustrates how little a four-point fit constrains timing at 8 GiB. Fit errors are maximum absolute residuals over the four measured sizes."))
        out.append(table(["Library","$a$ (ns)","$b$ (ns/dbl.)","Log err. (ns)","Log 8 GiB (ns)","Linear err. (ns)","Linear 8 GiB (ms)"],rows))
    out.append(escape("This is a projection of the tiny flat-memory timing trend. Selection depth, fanout, wire delays and memory organization can change far outside the fit. The 8 GiB estimate assumes wider physical addressing and a changed memory map. RV32 has a 4 GiB byte-address space, and this design fixes RAM at 0x80000000. Real systems use registers and small fast caches, then larger caches, banked SRAM and multi-cycle DRAM. A cache miss initiates a separate memory transaction. The pipeline stalls dependent work or overlaps other instructions across many short core clocks."))
    return "\n\n".join(out)


def reproduction(st):
    out=[section("Reproducing the measurements"),
         escape("Run these commands from the assignment repository on a Rutgers iLab machine with the supplied technology libraries and tool paths. Use a new, sufficiently large scratch directory for a fresh implementation. The experiment below uses a private directory under the home cache. A small quota on /tmp cannot hold the experiment matrix."),
         r"""\begin{verbatim}
make software
python3 scripts/count_instructions.py
python3 scripts/verify_rtl.py
python3 scripts/run_experiment.py --scratch "$HOME/.cache/cs505-f26-lab2-matrix"
python3 scripts/make_report.py
\end{verbatim}""",
         smalltitle("Starting from the course checkout and the four assembly files"),
         escape("Use course revision 7457966435b2. Place the four supplied .S files under software/benchmark/. In software/Makefile.in, add one SW_BUILD_VERILATOR_TEMPLATE invocation per name, following the gcd rule and linking main.S. In build.py, add their four .hex names to BENCHMARK with +max_cycles=20000. Preserve the longer timeouts for histogram, sieve127 and sqrt."),
         escape("For Task 2, set RAM_SIZE_BYTES to 256 in src/rv32i-memory/config.vh and select only asap7 when calling build_all_targets. In a fresh worktree run make. For Task 3, use one clean worktree or build directory per RAM size, change the same parameter to 256, 512, 1024 or 2048, and keep only targets ending in -soc. Set the library list to asap7, nan45 and sky130. Rebuild the software and designs in each worktree. Preserve or compress each result before recycling large temporary waveforms."),
         escape("On a stock run, the same values are available in synth/stdout.log, sta-timing/netlist-min-clock.rpt, sta-power-statistical/netlist.rpt and sta-power-vcd/. For an independent instruction count, trace valid fetch addresses and words on the single-cycle core from the first executed instruction through the EBREAK at the end. Check that the testbench reports PASS."),
         smalltitle("Retained data from this experiment"),
         escape("The driver copies the RTL into a separate directory for each configuration, sets RAM_SIZE_BYTES to the selected capacity, and uses the configured RTL sources, SDC and Liberty files. CPU-only targets use ASAP7 and 256 B. SoC targets cover all combinations of node and capacity. Each mapped design gets its own benchmark simulations and clock period."),
         escape("A single-cycle source-RTL monitor records instruction words and PCs through the final EBREAK. Taken branches are counted from the next PC. The independent functional runs use the uninstrumented testbenches. The gate-level runs check both the MMIO pass result and the expected trap. Each waveform covers benchmark execution. OpenSTA reads activity at the mapped DUT scope, rescales VCD transition densities to the measured clock period, and reports internal, switching and leakage watts."),
         escape("Raw evidence lives under results/<bytes>/<library>/<scope>-<design>/. The synthesis log provides chip area. period.rpt and units.log supply timing, and paths.rpt.gz retains individual paths. statistical.rpt supplies vectorless power. Each workload has a simulator log for pass/fail and cycles, a power report for total watts and a compressed power log for the activity annotation."),
         escape("The derived quantities in the design and workload tables are calculated from these files without rounding intermediate operands. Reported precision reflects formatting rather than additional timing or power accuracy.")]
    if extra_file("reproduction.txt"):
        out.append(extra_file("reproduction.txt"))
    return "\n\n".join(out)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,default=ROOT/"report.pdf")
    args=parser.parse_args()
    st=Study()
    with tempfile.TemporaryDirectory(prefix="cs505-report-") as tmp:
        workdir=Path(tmp)
        for t in TECHS:
            plot(st,workdir,t)
        chapters=[intro(st),predictions(),design_table(st),workload_table(st,"cpu"),
                  workload_table(st,"soc"),normalized_table(st),aggregate_baseline(st)+"\n\n"+findings(st),
                  pipeline_findings(st),power_findings(st)]
        chapters.extend(sweep_panel(st,t,i) for i,t in enumerate(TECHS,1))
        chapters.extend([sweep_discussion(st),energy_analysis(st),energy_conclusion(st)])
        chapters.append(reproduction(st))
        (workdir/"report.tex").write_text(HEADER+"\n"+r"\clearpage".join("\n"+c+"\n" for c in chapters)+"\n"+r"\end{document}")
        for _ in range(2):
            command=["pdflatex","-interaction=nonstopmode","-halt-on-error","report.tex"]
            result=subprocess.run(command,cwd=workdir,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            if result.returncode:
                raise RuntimeError(result.stdout[-3500:])
        for line in (workdir/"report.log").read_text(errors="replace").splitlines():
            if "Overfull" in line:
                print(line)
        shutil.copyfile(workdir/"report.pdf",args.output)
        print(f"Created {args.output} from {len(st.keys)} configuration slots.")


if __name__=="__main__":
    main()
