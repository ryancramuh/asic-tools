#!/usr/bin/env bash

verilator --version | grep -m1 "Verilator"
iverilog -v 2>&1 | grep -m1 "Icarus Verilog version"
yosys --version | grep -m1 "^Yosys"
ngspice --version | grep -m1 "ngspice"
printf "Magic " && magic --version | head -n1
klayout -v | grep -m1 "^KLayout"
printf "OpenROAD " && openroad -version | grep -E -m1 "^v[0-9]"
openlane --version | grep -m1 "^OpenLane"
