BASE_OUTDIR  := build
.DEFAULT_GOAL := default
SHELL        := /bin/bash
.SHELLFLAGS  := -e -o pipefail -c

###############################################################################
# TOOLS: YOSYS
###############################################################################
YOSYS        := /common/users/shared/fluxlab-tools/yosys-0.69/bin/yosys
YOSYS_SCRIPT := scripts/yosys.tcl

###############################################################################
# TOOLS: OpenSTA
###############################################################################
OPENSTA                := /common/users/shared/fluxlab-tools/opensta-2.2.0/bin/sta
OPENSTA_SCRIPT_TIMING  := scripts/opensta-timing.tcl
OPENSTA_SCRIPT_POWER   := scripts/opensta-power.tcl

###############################################################################
# TOOLS: Verilator
###############################################################################
# Testbench using the gate-level design
VERILATOR       := /common/users/shared/fluxlab-tools/verilator-nightly6oct/bin/verilator
# VERILATOR       := /common/users/shared/fluxlab-tools/verilator-5.052/bin/verilator
VERILATOR_BIN   := V$(TESTBENCH_TOP_NAME)
VERILATOR_FLAGS := -Wall -Wno-DECLFILENAME --trace --trace-underscore
SKYHD130_DEFS   := -DFUNCTIONAL -DUNIT_DELAY
VERILATOR_DEFS  := $(SKYHD130_DEFS)

###############################################################################
# SOFTWARE: run-time hex files
###############################################################################
SIM_HEX_PATH    := $(BASE_OUTDIR)/software
SIM_HEX         ?= rv32i-op.hex
SIM_ARGS        ?=
export SIM_HEX_PATH SIM_HEX SIM_ARGS

###############################################################################
# BASIC RECIPES
###############################################################################
.SUFFIXES:

.PRECIOUS: $(BASE_OUTDIR)/%/synth/netlist.v \
           $(BASE_OUTDIR)/%/sta-timing/netlist-min-clock.rpt \
           $(BASE_OUTDIR)/%/sta-power-statistical/netlist.rpt \
           $(BASE_OUTDIR)/%/sim-netlist/$(VERILATOR_BIN) \
           $(BASE_OUTDIR)/%/sim-source/$(VERILATOR_BIN) \
           $(BASE_OUTDIR)/%/sta-power-vcd/netlist-$(SIM_HEX).vcd \
           $(BASE_OUTDIR)/%/sta-power-vcd/source-$(SIM_HEX).vcd \
           $(BASE_OUTDIR)/%/.stamp.build

.PHONY: default software
default: software
	python3 build.py build

$(BASE_OUTDIR)/%/synth:
	mkdir -p $@

$(BASE_OUTDIR)/%/sta-timing:
	mkdir -p $@

$(BASE_OUTDIR)/%/sta-power-statistical:
	mkdir -p $@

$(BASE_OUTDIR)/%/sta-power-vcd:
	mkdir -p $@

$(BASE_OUTDIR)/%/sim-source:
	mkdir -p $@

$(BASE_OUTDIR)/%/sim-netlist:
	mkdir -p $@

.PHONY: clean
clean:
	rm -rf $(BASE_OUTDIR)

$(BASE_OUTDIR)/%/.stamp.build: $(BASE_OUTDIR)/%/sta-power-statistical/netlist.rpt $(BASE_OUTDIR)/%/sim-netlist/$(VERILATOR_BIN) $(BASE_OUTDIR)/%/sim-source/$(VERILATOR_BIN) | $(BASE_OUTDIR)/%
	touch $@

# make certain that .stamp.run targets re-run whenever the netlist*.rpt files don't exist
RUN_DIRS := $(patsubst %/.stamp.run,%,$(filter %/.stamp.run,$(MAKECMDGOALS)))
RUN_REPORTS := $(addsuffix /sta-power-vcd/netlist-$(SIM_HEX).rpt,$(RUN_DIRS))
$(RUN_REPORTS):

$(BASE_OUTDIR)/%/.stamp.run: $(BASE_OUTDIR)/%/.stamp.build $(BASE_OUTDIR)/%/sta-power-vcd/netlist-$(SIM_HEX).rpt | $(BASE_OUTDIR)/%
	touch $@

###############################################################################
# SOFTWARE DEFINITIONS
###############################################################################
include software/Makefile.in

###############################################################################
# OpenSTA (timing)
###############################################################################
# Run 1: Timing-only
$(BASE_OUTDIR)/%/sta-timing/netlist-min-clock.rpt: $(BASE_OUTDIR)/%/synth/netlist.v $(OPENSTA_SCRIPT_TIMING) $(MODULE_SDC_FILENAME) $(TECHLIB_LIB_FILENAME) | $(BASE_OUTDIR)/%/sta-timing
	$(info [MAKE] Calculating Timing)
	export STA_OUTDIR=$(BASE_OUTDIR)/$*/sta-timing; \
	export STA_TECHLIB_FILE=$(TECHLIB_LIB_FILENAME); \
	export STA_SOURCE_FILES=$<; \
	export STA_TOP_NAME=$(MODULE_TOP_NAME); \
	export STA_SDC_FILE=$(MODULE_SDC_FILENAME); \
	export STA_CLOCK_PERIOD=0.0; \
	export STA_TIMING_REPORT_NAME=$(@F); \
	$(OPENSTA) -no_splash -exit $(OPENSTA_SCRIPT_TIMING) 2>&1 | tee $(BASE_OUTDIR)/$*/sta-timing/opensta.log
	! grep -q '^Error:' $(BASE_OUTDIR)/$*/sta-timing/opensta.log
	test -s $@

# Run 2: switching power (independent of workload)
$(BASE_OUTDIR)/%/sta-power-statistical/netlist.rpt: $(BASE_OUTDIR)/%/synth/netlist.v $(OPENSTA_SCRIPT_POWER) $(BASE_OUTDIR)/%/sta-timing/netlist-min-clock.rpt | $(BASE_OUTDIR)/%/sta-power-statistical
	$(info [MAKE] Calculating Switching Power)
	export STA_OUTDIR=$(BASE_OUTDIR)/$*/sta-power-statistical; \
	export STA_TECHLIB_FILE=$(TECHLIB_LIB_FILENAME); \
	export STA_SOURCE_FILES=$<; \
	export STA_TOP_NAME=$(MODULE_TOP_NAME); \
	export STA_SDC_FILE=$(MODULE_SDC_FILENAME); \
	export STA_CLOCK_PERIOD=$$(cat $(BASE_OUTDIR)/$*/sta-timing/netlist-min-clock.rpt); \
	export STA_POWER_TYPE=0; \
	export STA_POWER_REPORT_NAME=$(@F); \
	export STA_VCD_FILENAME="none"; \
	export STA_TB_DUT_NAME="none"; \
	$(OPENSTA) -no_splash -exit $(OPENSTA_SCRIPT_POWER) 2>&1 | tee $(BASE_OUTDIR)/$*/sta-power-statistical/opensta.log
	! grep -q '^Error:' $(BASE_OUTDIR)/$*/sta-power-statistical/opensta.log
	test -s $@

###############################################################################
# Yosys (netlist synthesis)
###############################################################################
$(BASE_OUTDIR)/%/synth/netlist.v: $(MODULE_SOURCES) $(YOSYS_SCRIPT) $(TECHLIB_LIB_FILENAME) | $(BASE_OUTDIR)/%/synth
	$(info [MAKE] Synthesizing Netlist)
	export SYNTH_OUTDIR=$(BASE_OUTDIR)/$*/synth; \
	export SYNTH_TECHLIB_FILE=$(TECHLIB_LIB_FILENAME); \
	export SYNTH_SOURCE_FILES="$(MODULE_SOURCES)"; \
	export SYNTH_TOP_NAME=$(MODULE_TOP_NAME); \
	export SYNTH_NETLIST_FILE=$@; \
	export SYNTH_FLATTEN_EARLY=1; \
	$(YOSYS) -t -l $(BASE_OUTDIR)/$*/synth/stdout.log -c $(YOSYS_SCRIPT)

###############################################################################
# Verilator compilation (to generate the compiled testbenches)
###############################################################################
# based on netlist
$(BASE_OUTDIR)/%/sim-netlist/$(VERILATOR_BIN): $(BASE_OUTDIR)/%/synth/netlist.v $(TESTBENCH_SOURCES) $(TECHLIB_SIM_FILENAMES) scripts/verilator.vlt | $(BASE_OUTDIR)/%/sim-netlist
	$(info [MAKE] Simulating verilog)
	$(VERILATOR) -j 10 -Wno-fatal --cc --binary -exe --build --Mdir $(BASE_OUTDIR)/$*/sim-netlist \
		$(VERILATOR_FLAGS) $(VERILATOR_DEFS) $^ --top-module $(TESTBENCH_TOP_NAME) 2>&1 | tee $(BASE_OUTDIR)/$*/sim-netlist/compile-stdout.log

# based on sources
$(BASE_OUTDIR)/%/sim-source/$(VERILATOR_BIN): $(MODULE_SOURCES) $(TESTBENCH_SOURCES) $(TECHLIB_SIM_FILENAMES) scripts/verilator.vlt | $(BASE_OUTDIR)/%/sim-source
	$(info [MAKE] Simulating verilog)
	$(VERILATOR) -j 10 -Wno-fatal --cc --binary -exe --build --Mdir $(BASE_OUTDIR)/$*/sim-source \
		$(VERILATOR_FLAGS) $(VERILATOR_DEFS) $^ --top-module $(TESTBENCH_TOP_NAME) 2>&1 | tee $(BASE_OUTDIR)/$*/sim-source/compile-stdout.log

###############################################################################
# Verilator runs (to generate VCDs using different softwares)
###############################################################################
# netlist VCDs
$(BASE_OUTDIR)/%/sta-power-vcd/netlist-$(SIM_HEX).vcd: $(BASE_OUTDIR)/%/sim-netlist/$(VERILATOR_BIN) $(SIM_HEX_PATH)/$(SIM_HEX) | $(BASE_OUTDIR)/%/sta-power-vcd
	@echo "Current time in nanoseconds: $$(date +%s%N)"
	$(BASE_OUTDIR)/$*/sim-netlist/$(VERILATOR_BIN) +hex=$(SIM_HEX_PATH)/$(SIM_HEX) +vcd=$@ $(SIM_ARGS) 2>&1 | tee $(BASE_OUTDIR)/$*/sta-power-vcd/verilator-netlist-$(SIM_HEX).log
	! grep -q '^TEST_RESULT FAIL' $(BASE_OUTDIR)/$*/sta-power-vcd/verilator-netlist-$(SIM_HEX).log
	@echo "Current time in nanoseconds: $$(date +%s%N)"
	
# source VCDs (for debugging, since OpenSTA can't actually consume behavioral source)
$(BASE_OUTDIR)/%/sta-power-vcd/source-$(SIM_HEX).vcd: $(BASE_OUTDIR)/%/sim-source/$(VERILATOR_BIN) $(SIM_HEX_PATH)/$(SIM_HEX) | $(BASE_OUTDIR)/%/sta-power-vcd
	@echo "Current time in nanoseconds: $$(date +%s%N)"
	$(BASE_OUTDIR)/$*/sim-source/$(VERILATOR_BIN) +hex=$(SIM_HEX_PATH)/$(SIM_HEX) +vcd=$@ $(SIM_ARGS) 2>&1 | tee $(BASE_OUTDIR)/$*/sta-power-vcd/verilator-source-$(SIM_HEX).log
	! grep -q '^TEST_RESULT FAIL' $(BASE_OUTDIR)/$*/sta-power-vcd/verilator-source-$(SIM_HEX).log
	@echo "Current time in nanoseconds: $$(date +%s%N)"

###############################################################################
# OpenSTA (VCD power, for every VCD we generate)
###############################################################################
$(BASE_OUTDIR)/%/sta-power-vcd/netlist-$(SIM_HEX).rpt: $(BASE_OUTDIR)/%/synth/netlist.v $(OPENSTA_SCRIPT_POWER) $(BASE_OUTDIR)/%/sta-power-vcd/netlist-$(SIM_HEX).vcd $(BASE_OUTDIR)/%/sta-timing/netlist-min-clock.rpt | $(BASE_OUTDIR)/%/sta-power-vcd
	$(info [MAKE] Calculating VCD Power from netlist)
	export STA_OUTDIR=$(BASE_OUTDIR)/$*/sta-power-vcd; \
	export STA_TECHLIB_FILE=$(TECHLIB_LIB_FILENAME); \
	export STA_SOURCE_FILES=$<; \
	export STA_TOP_NAME=$(MODULE_TOP_NAME); \
	export STA_SDC_FILE=$(MODULE_SDC_FILENAME); \
	export STA_CLOCK_PERIOD=$$(cat $(BASE_OUTDIR)/$*/sta-timing/netlist-min-clock.rpt); \
	export STA_POWER_TYPE=1; \
	export STA_POWER_REPORT_NAME=$(@F); \
	export STA_VCD_FILENAME=$(BASE_OUTDIR)/$*/sta-power-vcd/netlist-$(SIM_HEX).vcd; \
	export STA_TB_DUT_NAME=$(TESTBENCH_TOP_NAME); \
	$(OPENSTA) -no_splash -exit $(OPENSTA_SCRIPT_POWER) 2>&1 | tee -a $(BASE_OUTDIR)/$*/sta-power-vcd/opensta-netlist-$(SIM_HEX).log
	! grep -q '^Error:' $(BASE_OUTDIR)/$*/sta-power-vcd/opensta-netlist-$(SIM_HEX).log
	test -s $@
