#!/bin/bash
set -e
SIMDIR="sim"
SYNTHDIR="synth"
RTLDIR="rtl_yosys"
SIMLIB="/home/hh/miniconda3/share/yosys/simlib.v"

echo "=== Compiling gate-level simulation (S=4, D=8, BK=2) ==="

iverilog -g2012 -Wall \
  -D GATE_SIM \
  -I ${RTLDIR} \
  -o ${SIMDIR}/tb_scheduler_gate_small.vvp \
  ${SIMLIB} \
  ${SYNTHDIR}/fa_exp_approx_netlist_small.v \
  ${SYNTHDIR}/fa_recip_approx_netlist_small.v \
  ${SYNTHDIR}/fa_dot_pe_netlist_small.v \
  ${SYNTHDIR}/fa_softmax_online_netlist_small.v \
  ${RTLDIR}/fa_scheduler.sv \
  ${SIMDIR}/tb_scheduler_gate_small.sv

echo "=== Compilation OK, running ==="
time vvp ${SIMDIR}/tb_scheduler_gate_small.vvp
echo "=== Done ==="
