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
GOLD = `tput setaf 220`
GREEN = `tput setaf 2`
BLUE    = `tput setaf 4`
MAGENTA = `tput setaf 5`
CYAN    = `tput setaf 6`
WHITE   = `tput setaf 7`
GREY    = `tput setaf 8`   # dim gray
BRIGHT_RED    = `tput setaf 9`
BRIGHT_GREEN  = `tput setaf 10`
BRIGHT_YELLOW = `tput setaf 11`
BRIGHT_BLUE   = `tput setaf 12`
BRIGHT_MAGENTA= `tput setaf 13`
BRIGHT_CYAN   = `tput setaf 14`
BRIGHT_WHITE  = `tput setaf 15`
ORANGE        = `tput setaf 214`
PINK          = `tput setaf 213`
PURPLE        = `tput setaf 93`
RED = `tput setaf 1`
RESET = `tput sgr0`

TEST_GREEN := $(shell tput setaf 2)
TEST_ORANGE := $(shell tput setaf 214)
TEST_RED := $(shell tput setaf 1)
TEST_RESET := $(shell tput sgr0)

.PHONY: rars
rars:
	java -jar asm/rars.jar

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

## Verilator Simulation ###
sim: $(SIMS) 

sim/%: FORCE
	make -s $(subst /,, $(basename $*))

## Icarus Simulation ###

isim: 
	@ICARUS=1 make sim

isim/%: FORCE
	@$(MAKE) -s ICARUS=1 sim/$*


## Gate Level Simulation ###
RECENT=$(shell ls runs | tail -n 1)
GL_NAME =$(shell ls runs/$(RECENT)/final/pnl/)

glsim/%: FORCE
	@mkdir -p gl
	@cat scripts/gatelevel.vh runs/$(RECENT)/final/pnl/$(GL_NAME) > gl/$(GL_NAME)
	@$(MAKE) -s GL=1 sim/$*

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
	@printf "$(ORANGE)STA requires an sta.tcl to be configured inside of scripts$(RESET)\n"
	sta scripts/sta.tcl
	
OPENLANE_CONF ?= config.*
openlane:
	@`which openlane` --flow Classic $(OPENLANE_CONF)
	@cd runs && rm -f recent && ln -sf `ls | tail -n 1` recent

openlane_sta:
	@`which openlane` --flow Classic $(OPENLANE_CONF) -T openroad.floorplan
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

.PHONY: help
help:
	@printf "\n$(GREEN)Linting$(RESET)\n" 
	@printf "$(GREEN)lint$(RESET) to lint all your rtl\n"

	@printf "\n$(BRIGHT_CYAN)Verilator Simulation (0,1)$(RESET)\n"
	@printf "$(BRIGHT_CYAN)sim$(RESET) to simulate all testbenches with Verilator\n"
	@printf "$(BRIGHT_CYAN)sim/$(RESET) to simulate one testbench with Verilator\n"
	
	@printf "\n$(ORANGE)Icarus Simulation (1, 0, X, Z)$(RESET)\n"
	@printf "$(ORANGE)isim$(RESET) to simulate all testbenches with Icarus Verilog\n"
	@printf "$(ORANGE)isim/$(RESET) to simulate one testbench with Icarus Verilog\n"
	
	@printf "\n$(BRIGHT_BLUE)Icarus Gate-Level Simulation (1, 0, X, Z)$(RESET)\n"
	@printf "$(BRIGHT_BLUE)glsim/$(RESET) to simulate your design with gate-level simulation with Icarus\n"

	@printf "\n$(PURPLE)Synthesis$(RESET)\n"
	@printf "$(PURPLE)synth$(RESET) runs synthesis with Yosys 0.51\n"
	@printf "requires synth.ys to be configured in scripts/ \n"
	
	@printf "\n$(MAGENTA)OpenSTA$(RESET)\n"
	@printf "$(MAGENTA)sta$(RESET)\n"
	@printf "requires sta.tcl to be configured in scripts/\n" 
	@printf "run \"make openlane_sta\" before trying this\n"
	
	@printf "\n$(BLUE)Openlane$(RESET)\n"
	@printf "$(BLUE)openlane$(RESET) runs the OpenLane 2.0 Classic Flow\n"
	@printf "requires config.yaml or config.json in the project home\n"

	@printf "\n$(RED)RARS$(RESET)\n"
	@printf "$(RED)rars$(RESET) opens RARS\n"
	@printf "requires rars.jar in asm/\n"

	@printf "\n$(PINK)Log all relevant info about tools versions and pdk paths$(RESET)\n"
	@printf "$(PINK)log$(RESET) loads .logs with relevant info\n"

	@printf "\n$(BRIGHT_YELLOW)Remove build artifacts and logs$(RESET)\n"
	@printf "$(BRIGHT_YELLOW)clean$(RESET) removes tool generated output\n"

	@printf "\n$(GOLD)Project Generation$(RESET)\n"
	@printf "$(GOLD)proj$(RESET)\n"
	@printf "pass PROJECT= to name your project\n" 
	@printf "ex: make proj PROJECT=mul\n\n"

PROJECT ?= project

# Creates project using Makefile, scripts/, and PROJECT_NAME
.PHONY: proj
proj:
	@if [ ! -d scripts ]; then \
		echo "Error: scripts/ directory not found!"; \
		exit 1; \
	fi
	@echo "Creating $(PROJECT)/ with subfolders rtl, sim, logs, synth, and scripts and Makefile\n"
	@mkdir -p $(PROJECT)/rtl
	@mkdir -p $(PROJECT)/sim
	@mkdir -p $(PROJECT)/synth
	@mkdir -p $(PROJECT)/logs
	@mkdir -p $(PROJECT)/asm
	@touch $(PROJECT)/rtl/$(PROJECT).sv
	@mkdir $(PROJECT)/sim/tb_$(PROJECT)
	@touch $(PROJECT)/sim/tb_$(PROJECT)/tb_$(PROJECT).sv
	@touch $(PROJECT)/config.yaml
	@echo "Copying scripts/ into $(PROJECT)/"
	@cp -r scripts $(PROJECT)/
	@echo "Copying Makefile..."
	@cp Makefile $(PROJECT)/

.PHONY: VERILOG_SOURCES
VERILOG_SOURCES: 
	@echo $(realpath $(RTL_SRCS))

