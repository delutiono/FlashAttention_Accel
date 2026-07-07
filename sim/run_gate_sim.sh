#!/bin/bash
# Gate-level simulation compile & run
# Usage: bash sim/run_gate_sim.sh

set -e

SIMDIR="sim"
SYNTHDIR="synth"
RTLDIR="rtl_yosys"
SIMLIB="/home/hh/miniconda3/share/yosys/simlib.v"

echo "=== Compiling gate-level simulation ==="

# Only include netlists that are actually instantiated in the hierarchy:
# fa_dot_pe, fa_softmax_online (includes fa_exp_approx), fa_recip_approx, fa_regfile

iverilog -g2012 -Wall \
  -D GATE_SIM \
  -I ${RTLDIR} \
  -o ${SIMDIR}/tb_fa_top_gate.vvp \
  ${SIMLIB} \
  ${SYNTHDIR}/fa_recip_approx_netlist.v \
  ${SYNTHDIR}/fa_dot_pe_netlist.v \
  ${SYNTHDIR}/fa_softmax_online_netlist.v \
  ${SYNTHDIR}/fa_regfile_netlist.v \
  ${RTLDIR}/fa_scheduler.sv \
  ${RTLDIR}/fa_accel_top.sv \
  ${SIMDIR}/tb_fa_top_gate.sv

echo "=== Compilation OK ==="
echo "=== Running gate-level simulation ==="

vvp ${SIMDIR}/tb_fa_top_gate.vvp

echo "=== Simulation done ==="
