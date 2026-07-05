#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$BASE_DIR/../.." && pwd)

XRUN=${XRUN:-xrun}
CASE=${1:-zero}
CASE_NAME=${CASE_NAME:-genus_s256_d64_seed100}
RUN_DIR=${RUN_DIR:-"$REPO_ROOT/artifacts/runs/xcelium_baseline_${CASE_NAME}_${CASE}"}
WORK_DIR=${WORK_DIR:-"$REPO_ROOT/build/xcelium_baseline/fa_top_${CASE}"}

mkdir -p "$RUN_DIR" "$WORK_DIR"

if ! command -v "$XRUN" >/dev/null 2>&1; then
  echo "ERROR: Xcelium command '$XRUN' was not found in PATH." >&2
  echo "Load your Cadence/Xcelium environment first, or set XRUN=/full/path/to/xrun." >&2
  exit 127
fi

cd "$REPO_ROOT"

common_xrun_args=(
  -64bit
  -sv
  -define FUNCTIONAL
  -delay_mode zero
  -timescale 1ns/1ps
  -access +rwc
  -notimingchecks
  -f "$BASE_DIR/filelists/fa_top_gate.f"
  "$BASE_DIR/models/axi_mem_model_128.sv"
  -input "$BASE_DIR/tcl/run_gate_func.tcl"
  -xmlibdirname "$WORK_DIR"
)

extra_xrun_args=()

case "$CASE" in
  smoke)
    tb=tb_fa_top_axi_lite_smoke
    tb_file="$BASE_DIR/tb/tb_fa_top_axi_lite_smoke.sv"
    ;;
  zero)
    tb=tb_fa_top_zero_s256
    tb_file="$BASE_DIR/tb/tb_fa_top_zero_s256.sv"
    extra_xrun_args=(-define FA_GATE_DIAG)
    ;;
  zero_trace)
    tb=tb_fa_top_zero_s256
    tb_file="$BASE_DIR/tb/tb_fa_top_zero_s256.sv"
    extra_xrun_args=(-define FA_GATE_DIAG -define FA_GATE_TRACE)
    ;;
  zero_xtrace|zero_wrtrace)
    tb=tb_fa_top_zero_s256
    tb_file="$BASE_DIR/tb/tb_fa_top_zero_s256.sv"
    extra_xrun_args=(-define FA_GATE_DIAG -define FA_GATE_TRACE -define FA_GATE_XTRACE -define FA_GATE_XSTOP)
    ;;
  scoreboard)
    tb=tb_fa_top_s256_scoreboard
    tb_file="$BASE_DIR/tb/tb_fa_top_s256_scoreboard.sv"
    extra_xrun_args=(-define FA_GATE_DIAG)
    ;;
  scoreboard_trace)
    tb=tb_fa_top_s256_scoreboard
    tb_file="$BASE_DIR/tb/tb_fa_top_s256_scoreboard.sv"
    extra_xrun_args=(-define FA_GATE_DIAG -define FA_GATE_TRACE)
    ;;
  *)
    echo "usage: $0 [smoke|zero|zero_trace|zero_xtrace|zero_wrtrace|scoreboard|scoreboard_trace]" >&2
    exit 2
    ;;
esac

"$XRUN" "${common_xrun_args[@]}" "${extra_xrun_args[@]}" "$tb_file" -top "$tb" -l "$RUN_DIR/xrun.log"
