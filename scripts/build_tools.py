#!/usr/bin/env python3
import sys
import os
import time
import subprocess as sp
from pathlib import Path

# ANSI escape sequences
RED = '\033[31m'
GREEN = '\033[32m'
YELLOW = '\033[33m'
RESET = '\033[0m'

# available technology libraries
TECH_LIBS = {
    "asap7"   : {
        "lib" : "/common/users/shared/fluxlab-tools/techlibs/asap7sc7p5t_ALL_LVT_TT_nldm_211120.lib.gz",              
        "sim" : ["/common/users/shared/fluxlab-tools/techlibs/asap7sc7p5t_ALL_LVT_TT_nldm_211120.v"]
    },
    "nan45"       : {
        "lib" : "/common/users/shared/fluxlab-tools/techlibs/NangateOpenCellLibrary_typical.lib",
        "sim" : ["/common/users/shared/fluxlab-tools/techlibs/NangateOpenCellLibrary.v"]
    },
    "nan45-nand2"     : {
        "lib" : "/common/users/shared/fluxlab-tools/techlibs/NangateOpenCellLibrary_typical_NAND2.lib",
        "sim" : ["/common/users/shared/fluxlab-tools/techlibs/NangateOpenCellLibrary.v"]
    },
    "sky130"     : {
        "lib" : "/common/users/shared/fluxlab-tools/techlibs/sky130hd_tt.lib",
        "sim" : ["/common/users/shared/fluxlab-tools/techlibs/sky130hd_tt.v", "/common/users/shared/fluxlab-tools/techlibs/sky130hd_primitives.v"]
    }
}

# Builds every module/library pair; returns nonzero if any child Make job fails.
def build_all_targets(target_list: list, techlib_list: dict, build_dirname: str, max_parallel_jobs: int) -> int:
    print(f"Building {len(target_list)} modules using {len(techlib_list)} technology libraries")
    print(f"    Modules: {[i for i in target_list]}")
    print(f"    Techlibs: {techlib_list}")
    Path(build_dirname).mkdir(parents=False, exist_ok=True)

    #
    # build job lists
    #
    job_list = []
    job_deps = {}
    for target_name in target_list:
        for techlib_name in techlib_list:
            target_fullname = os.path.join(build_dirname, target_name, techlib_name)
            Path(target_fullname).mkdir(parents=True, exist_ok=True)
            
            env = os.environ.copy()
            env["TECHLIB_LIB_FILENAME"] = TECH_LIBS[techlib_name]["lib"]
            env["TECHLIB_SIM_FILENAMES"] = " ".join(TECH_LIBS[techlib_name]["sim"])
            env["MODULE_SOURCES"] = target_list[target_name]["sources"]
            env["MODULE_TOP_NAME"] = target_list[target_name]["top"]
            env["MODULE_SDC_FILENAME"] = target_list[target_name]["sdc"]
            env["TESTBENCH_SOURCES"] = target_list[target_name]["tb sources"]
            env["TESTBENCH_TOP_NAME"] = target_list[target_name]["tb top"]
            env["SIM_HEX"] = "NONE-build-only" 
            env["SIM_ARGS"] = "NONE-build-only"

            out_file = f"{target_fullname}/stdout-build-only.log"
            err_file = f"{target_fullname}/stderr-build-only.log"

            build_job_idx = len(job_list)
            job_list.append({
                "name" : f"BUILD {target_fullname}",
                "desc" : f"BUILD target name \"{target_name}\" using technology library \"{techlib_name}\" (output dir: \"{target_fullname}\")",
                "env" : env,
                "stdout" : out_file,
                "stderr" : err_file,
                "args" : ["make", f"BASE_OUTDIR={build_dirname}", f"{target_fullname}/.stamp.build", "-r"]
            })
            job_deps[build_job_idx] = ()

            for sim_hexfile, sim_args in target_list[target_name]["sim args"].items():
                env = os.environ.copy()
                env["TECHLIB_LIB_FILENAME"] = TECH_LIBS[techlib_name]["lib"]
                env["TECHLIB_SIM_FILENAMES"] = " ".join(TECH_LIBS[techlib_name]["sim"])
                env["MODULE_SOURCES"] = target_list[target_name]["sources"]
                env["MODULE_TOP_NAME"] = target_list[target_name]["top"]
                env["MODULE_SDC_FILENAME"] = target_list[target_name]["sdc"]
                env["TESTBENCH_SOURCES"] = target_list[target_name]["tb sources"]
                env["TESTBENCH_TOP_NAME"] = target_list[target_name]["tb top"]
                env["SIM_HEX"] = sim_hexfile
                env["SIM_ARGS"] = " ".join(sim_args)

                out_file = f"{target_fullname}/stdout-{sim_hexfile}.log"
                err_file = f"{target_fullname}/stderr-{sim_hexfile}.log"

                run_job_idx = len(job_list)
                job_list.append({
                    "name" : f"RUN {target_fullname} w/ {sim_hexfile}",
                    "desc" : f"RUN target name \"{target_name}\" using technology library \"{techlib_name}\" (output dir: \"{target_fullname}\")",
                    "env" : env,
                    "stdout" : out_file,
                    "stderr" : err_file,
                    "args" : ["make", f"BASE_OUTDIR={build_dirname}", f"{target_fullname}/.stamp.run", "-r"]
                })
                job_deps[run_job_idx] = (build_job_idx,)

    #
    # run jobs
    #
    assert max_parallel_jobs > 0
    log_file_handles = []
    running_jobs = []
    completed_jobs = dict({}) # job_idx : exit_code
    pending_jobs = list(range(len(job_list)))

    try:
        while pending_jobs or running_jobs:
            made_progress = False

            # 1. Collect completed processes.
            for job_idx, proc in running_jobs[:]:
                exit_code = proc.poll()
                if exit_code is not None:
                    color = GREEN if exit_code == 0 else RED
                    print(color + f"Job \"{job_list[job_idx]['name']}\" (PID {proc.pid}) finished with exit code {exit_code}" + RESET)
                    running_jobs.remove((job_idx, proc))
                    completed_jobs[job_idx] = exit_code
                    made_progress = True

            # 2. Skip failed dependents and launch ready jobs up to capacity.
            for job_idx in pending_jobs[:]:
                job = job_list[job_idx]
                dep_list = job_deps[job_idx]

                if any(dep in completed_jobs and completed_jobs[dep] != 0 for dep in dep_list):
                    print("Skipping due to dependency failure: " + job["desc"])
                    completed_jobs[job_idx] = 1
                    pending_jobs.remove(job_idx)
                    made_progress = True
                    continue

                if not all(dep in completed_jobs for dep in dep_list):
                    continue
                if len(running_jobs) >= max_parallel_jobs:
                    continue
                
                print(f"Launching: " + job["desc"])
                
                out_file = open(job["stdout"], "w", encoding="utf-8")
                err_file = open(job["stderr"], "w", encoding="utf-8")
                log_file_handles.extend([out_file, err_file])

                proc = sp.Popen(args=job["args"], env=job["env"], stdout=out_file, stderr=err_file)
                running_jobs.append((job_idx, proc))
                pending_jobs.remove(job_idx)
                made_progress = True

            # 3. Detect unresolved dependencies, or pause before polling again.
            if pending_jobs and not running_jobs and not made_progress:
                raise ValueError("Unresolved dependencies or dependency cycle")

            if running_jobs:
                time.sleep(0.1)
    finally:
        for f in log_file_handles:
            f.close()
    
    # return whether all jobs completed successfully
    for job_idx in completed_jobs:
        if completed_jobs[job_idx] != 0:
            return 1
    return 0

# formats target modules in a standardized way
def format_target(sources : list, topname : str, sdc_filename: str, tb_sources: list, tb_top_name: str, hexfiles: dict) -> dict:
    return {
        "sources" : " ".join(sources),
        "top" : topname,
        "sdc" : sdc_filename,
        "tb sources" : " ".join(tb_sources),
        "tb top" : tb_top_name,
        "sim args" : hexfiles
    }
