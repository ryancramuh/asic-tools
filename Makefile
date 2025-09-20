INC_DIR := ./include

RTL_SRCS 	:= $(shell find rtl -name '*.sv' -or -name '*.v')
INCLUDE_DIRS := $(sort $(dir $(shell find . -name '*.svh')))
RTL_DIRS	 := $(sort $(dir $(RTL_SRCS)))
# Include both Include and RTL directories for linting
LINT_INCLUDES := $(foreach dir, $(INCLUDE_DIRS) $(RTL_DIRS), -I$(realpath $(dir))) -I$(PDKPATH) 

SIM_DIR = ./sim
SIM_SUBDIRS = $(shell cd $(SIM_DIR) && ls -d */ | grep -v "__pycache__" )
SIMS = $(SIM_SUBDIRS:/=)

# Main Linter and Simulatior is Verilator
LINTER := verilator
SIMULATOR := verilator
SIMULATOR_ARGS := --binary --timing --trace --trace-structs \
	--assert --timescale 1ns --quiet --Mdir verilator_lib
SIMULATOR_BINARY := ./verilator_lib/V*
SIMULATOR_SRCS := *.sv
# Optional use of Icarus as Linter and Simulator
ifdef ICARUS
SIMULATOR := iverilog
SIMULATOR_ARGS := -g2012
SIMULATOR_BINARY := a.out
SIMULATOR_SRCS := $(foreach src, $(RTL_SRCS), $(realpath $(src))) *.sv
SIM_TOP := `$(shell pwd)/scripts/top.sh -s`
# LINT_INCLUDES := ""
endif
# Gate Level Verification
ifdef GL
SIMULATOR := iverilog
LINT_INCLUDES := -I$(PDKPATH) -I$(realpath gl)
SIMULATOR_ARGS := -g2012 -DFUNCTIONAL -DUSE_POWER_PINS 
SIMULATOR_BINARY := a.out
SIMULATOR_SRCS = $(realpath gl)/*  *.sv
endif


LINT_OPTS += --lint-only --timing $(LINT_INCLUDES)

# Text formatting for tests
BOLD = `tput bold`
GREEN = `tput setaf 2`
ORANG = `tput setaf 214`
RED = `tput setaf 1`
RESET = `tput sgr0`

TEST_GREEN := $(shell tput setaf 2)
TEST_ORANGE := $(shell tput setaf 214)
TEST_RED := $(shell tput setaf 1)
TEST_RESET := $(shell tput sgr0)

.PHONY: rars
rars:
	java -jar rars.jar

.PHONY: list-versions list-libs list-spice list-magicrc logs

list-versions:
	@./scripts/extract_version.sh > logs/tool-version.log

list-libs:
	@find /foss/pdks/volare/sky130/versions -name "*.lib" \
	    | grep sky130_fd_sc_hd > logs/pdk_libs.log

list-spice:
	@find /foss/pdks/volare/sky130/versions -name "*.spice" \
	    | grep sky130_fd_sc_hd > logs/pdk_spice.log

list-magicrc:
	@find /foss/pdks/volare/sky130/versions/ -name "*.magicrc" | grep sky130A > logs/pdk_magicrc.log

# larger target
logs: list-versions list-libs list-spice list-magicrc

all: lint_all sim

lint: lint_all

.PHONY: lint_all
lint_all: 
	@printf "\n$(GREEN)$(BOLD) ----- Linting All Modules ----- $(RESET)\n"
	@for src in $(RTL_SRCS); do \
		top_module=$$(basename $$src .sv); \
		top_module=$$(basename $$top_module .v); \
		printf "Linting $$src . . . "; \
		if $(LINTER) $(LINT_OPTS) --top-module $$top_module $$src > /dev/null 2>&1; then \
			printf "$(GREEN)PASSED$(RESET)\n"; \
		else \
			printf "$(RED)FAILED$(RESET)\n"; \
			$(LINTER) $(LINT_OPTS) --top-module $$top_module $$src; \
		fi; \
	done

.PHONY: lint_top
lint_top:
	@printf "\n$(GREEN)$(BOLD) ----- Linting $(TOP_MODULE) ----- $(RESET)\n"
	@printf "Linting Top Level Module: $(TOP_FILE)\n";
	$(LINTER) $(LINT_OPTS) --top-module $(TOP_MODULE) $(TOP_FILE)


sim: $(SIMS) 

sim/%: FORCE
	make -s $(subst /,, $(basename $*))

isim: 
	@ICARUS=1 make sim

RECENT=$(shell ls runs | tail -n 1)
GL_NAME =$(shell ls runs/$(RECENT)/final/pnl/)
.PHONY: gl
glsim:
	@mkdir -p gl
	@cat scripts/gatelevel.vh runs/$(RECENT)/final/pnl/$(GL_NAME) > gl/$(GL_NAME)
	@GL=1 make sim

.PHONY: $(SIMS)
$(SIMS): 
	@printf "\n$(GREEN)$(BOLD) ----- Running Test: $@ ----- $(RESET)\n"
	@printf "\n$(BOLD) Building with $(SIMULATOR)... $(RESET)\n"

# Build With Simulator
	@cd $(SIM_DIR)/$@;\
		$(SIMULATOR) $(SIMULATOR_ARGS) $(SIMULATOR_SRCS) $(LINT_INCLUDES) $(SIM_TOP) > build.log
	
	@printf "\n$(BOLD) Running... $(RESET)\n"

# Run Binary and Check for Error in Result
	@if cd $(SIM_DIR)/$@;\
		./$(SIMULATOR_BINARY) > results.log \
		&& !( cat results.log | grep -qi error ) \
		then \
			printf "$(GREEN)PASSED $@$(RESET)\n"; \
		else \
			printf "$(RED)FAILED $@$(RESET)\n"; \
			cat results.log; \
		fi; \

COCOSIM_DIR = ./cocotests
COCOSIM_SUBDIRS = $(shell cd $(COCOSIM_DIR) && ls -d */ | grep -v "__pycache__" )
COCOSIMS = $(COCOSIM_SUBDIRS:/=)
.PHONY: cocotests
cocotests:
	@$(foreach test,  $(COCOSIMS), make -sC $(COCOSIM_DIR)/$(test);)

SYNTH_SRC = scripts/synth.ys
.PHONY: synth
synth:
	@printf "$(GREEN)========== Running Synthesis ===========$(RESET)\n"
	@yosys -s $(SYNTH_SRC) > logs/synth.log 2>&1 && \
	  echo "$(GREEN)Synthesis PASSED.$(RESET)" || \
	  ( echo "$(RED)Synthesis FAILED! See logs/synth.log for details.$(RESET)" && \
	    tail -n 20 synth.log && \
	    exit 1 )

.PHONY: sta
sta:
	sta scripts/sta.tcl

OPENLANE_CONF ?= scripts/config.*
openlane:
	@`which openlane` --flow Classic $(OPENLANE_CONF)
	@cd runs && rm -f recent && ln -sf `ls | tail -n 1` recent

%.json %.yaml: FORCE
	@echo $@
	OPENLANE_CONF=$@ make openlane

FORCE: ;

openroad:
	scripts/openroad_launch.sh | openroad

.PHONY: clean
clean:
	@printf "Removing Build Files: \n"

	@find sim -iname "*.vcd"  -exec rm -v {} \;
	@find sim -iname "a.out"  -exec rm -v {} \;
	@find sim -iname "*.log"  -exec rm -v {} \;
	@find sim -iname "obj_dir" -exec rm -rv {} \;

	@find synth -iname "*.spice" -exec rm -v {} \;
	@find synth -iname "*.dot"   -exec rm -v {} \;
	@find synth -iname "*.sp"    -exec rm -v {} \;
	@find synth -iname "*.log"   -exec rm -v {} \;
	@find synth -iname "*.sv"    -exec rm -v {} \;
	@find synth -iname "*.v"     -exec rm -v {} \;
	@find synth -iname "*.il"    -exec rm -v {} \;

	@find logs -iname "*.log"    -exec rm -v {} \;

.PHONY: VERILOG_SOURCES
VERILOG_SOURCES: 
	@echo $(realpath $(RTL_SRCS))

