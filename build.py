#!/usr/bin/env python3
import sys
import argparse

import scripts.build_tools as build_tools

def configure_cpu_build() -> dict:
    target_list = {}

    rv32i_single_cycle_cpu_sources = ["src/rv32i-common/" + basename for basename in ["alu.v", "branch_comparator.v", "immgen.v", "mem_aligner.v"]] \
        + ["src/rv32i-memory/" + basename for basename in ["mem-2r-1w-asyncr-syncw-1x8bit.v"]] \
        + ["src/rv32i-single-cycle/cpu.v"]

    rv32i_multi_cycle_cpu_sources = ["src/rv32i-common/" + basename for basename in ["alu.v", "branch_comparator.v", "immgen.v", "mem_aligner.v"]] \
        + ["src/rv32i-memory/" + basename for basename in ["mem-1rw-asyncr-syncw-1x8bit.v"]] \
        + ["src/rv32i-multi-cycle-single-bus/cpu.v"]

    rv32i_three_stage_cpu_sources = ["src/rv32i-common/" + basename for basename in ["alu.v", "branch_comparator.v", "immgen.v", "mem_aligner.v"]] \
        + ["src/rv32i-three-stage/cpu.v"]


    RV32I_INSTRUCTION_TESTS = {
        "rv32i-upper.hex" : [],
        "rv32i-op-imm.hex" : [],
        "rv32i-shift-imm.hex" : [],
        "rv32i-op.hex" : [],
        "rv32i-branch.hex" : [],
        "rv32i-jump.hex" : [],
        "rv32i-load.hex" : [],
        "rv32i-store.hex" : [],
        "rv32i-x0.hex" : [],
        "rv32i-system-ebreak.hex" : [],
        "rv32i-system-ecall.hex" : ["+expect_exception=EXCEPTION_ECALL"],
        "rv32i-illegal.hex" : ["+expect_exception=EXCEPTION_ILLEGAL_INSTRUCTION"],
        "rv32i-exception-imem-misaligned.hex" : ["+expect_exception=EXCEPTION_IMEM_MISALIGNMENT"],
        "rv32i-exception-imem-bus.hex" : ["+expect_exception=EXCEPTION_IMEM_BUS_ERROR"],
        "rv32i-exception-dmem-bus.hex" : ["+expect_exception=EXCEPTION_DMEM_BUS_ERROR"]
    }
    BENCHMARK = {
        "fib.hex" : [],
        "gcd.hex" : [],
        "popcount.hex" : [],
        "crc32.hex" : [],
        "histogram.hex" : ["+max_cycles=200000"],
        "sieve127.hex" : ["+max_cycles=200000"],
        "sqrt.hex" : ["+max_cycles=200000"],
        **{f"{name}.hex": ["+max_cycles=20000"]
           for name in ("low-ilp", "high-ilp", "low-energy", "high-energy")}
    }

    #
    # CPUs
    #
    target_list["rv32i-single-cycle-cpu"] = build_tools.format_target(
        sources      = rv32i_single_cycle_cpu_sources,
        topname      = "rv32i_single_cycle",
        sdc_filename = "src/rv32i-single-cycle/cpu.sdc",
        tb_sources   = ["src/rv32i-single-cycle/cpu_tb.v"],
        tb_top_name  = "tb",
        hexfiles     = BENCHMARK
    )
    
    target_list["rv32i-multi-cycle-single-bus-cpu"] = build_tools.format_target(
        sources      = rv32i_multi_cycle_cpu_sources,
        topname      = "rv32i_multi_cycle_single_bus",
        sdc_filename = "src/rv32i-multi-cycle-single-bus/cpu.sdc",
        tb_sources   = ["src/rv32i-multi-cycle-single-bus/cpu_tb.v"],
        tb_top_name  = "tb",
        hexfiles     = BENCHMARK
    )

    target_list["rv32i-three-stage-cpu"] = build_tools.format_target(
        sources      = rv32i_three_stage_cpu_sources,
        topname      = "rv32i_three_stage",
        sdc_filename = "src/rv32i-three-stage/cpu.sdc",
        tb_sources   = ["src/rv32i-three-stage/cpu_tb.v"],
        tb_top_name  = "tb",
        hexfiles     = BENCHMARK
    )

    #
    # SOCs
    #
    target_list["rv32i-single-cycle-soc"] = build_tools.format_target(
        sources      = rv32i_single_cycle_cpu_sources + ["src/rv32i-single-cycle/soc.v", "src/rv32i-memory/mem-1r-1rw-asyncr-syncw-4x8bit.v", "src/rv32i-memory/mem-1r-1rw-asyncr-syncw-1x8bit.v"],
        topname      = "soc",
        sdc_filename = "src/rv32i-single-cycle/soc.sdc",
        tb_sources   = ["src/rv32i-single-cycle/soc_tb.v"],
        tb_top_name  = "tb",
        hexfiles     = BENCHMARK
    )

    target_list["rv32i-multi-cycle-soc"] = build_tools.format_target(
        sources      = rv32i_multi_cycle_cpu_sources + ["src/rv32i-multi-cycle-single-bus/soc.v", "src/rv32i-memory/mem-1rw-asyncr-syncw-4x8bit.v"],
        topname      = "soc",
        sdc_filename = "src/rv32i-multi-cycle-single-bus/soc.sdc",
        tb_sources   = ["src/rv32i-multi-cycle-single-bus/soc_tb.v"],
        tb_top_name  = "tb",
        hexfiles     = BENCHMARK
    )

    target_list["rv32i-three-stage-soc"] = build_tools.format_target(
        sources      = rv32i_three_stage_cpu_sources + ["src/rv32i-three-stage/soc.v", "src/rv32i-memory/mem-1r-1rw-asyncr-syncw-4x8bit.v", "src/rv32i-memory/mem-1r-1rw-asyncr-syncw-1x8bit.v"],
        topname      = "soc",
        sdc_filename = "src/rv32i-three-stage/soc.sdc",
        tb_sources   = ["src/rv32i-three-stage/soc_tb.v"],
        tb_top_name  = "tb",
        hexfiles     = BENCHMARK
    )

    return target_list

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description="Build and benchmark the RV32I designs.")
    parser.add_argument("output", help="build directory, e.g. build")
    parser.add_argument("--tech", choices=build_tools.TECH_LIBS, nargs="+", default=["asap7"])
    parser.add_argument("--soc-only", action="store_true")
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    targets = configure_cpu_build()
    if args.soc_only:
        targets = {name: target for name, target in targets.items() if name.endswith("-soc")}
    sys.exit(build_tools.build_all_targets(targets, args.tech, args.output, args.jobs))
