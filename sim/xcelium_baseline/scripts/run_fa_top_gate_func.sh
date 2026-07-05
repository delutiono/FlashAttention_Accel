#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
if [[ -d "$BASE_DIR/../../.git" ]]; then
  OUT_ROOT=$(cd "$BASE_DIR/../.." && pwd)
else
  OUT_ROOT="$BASE_DIR"
fi

XRUN=${XRUN:-xrun}
CASE=${1:-zero}
CASE_NAME=${CASE_NAME:-genus_s256_d64_seed100}
RUN_DIR=${RUN_DIR:-"$OUT_ROOT/artifacts/runs/xcelium_baseline_${CASE_NAME}_${CASE}"}
WORK_DIR=${WORK_DIR:-"$OUT_ROOT/build/xcelium_baseline/fa_top_${CASE}"}

mkdir -p "$RUN_DIR" "$WORK_DIR"

if ! command -v "$XRUN" >/dev/null 2>&1; then
  echo "ERROR: Xcelium command '$XRUN' was not found in PATH." >&2
  echo "Load your Cadence/Xcelium environment first, or set XRUN=/full/path/to/xrun." >&2
  exit 127
fi

cd "$BASE_DIR"

common_xrun_args=(
  -64bit
  -sv
  -timescale 1ns/1ps
  -access +rwc
  "models/axi_mem_model_128.sv"
  -input "tcl/run_gate_func.tcl"
  -xmlibdirname "$WORK_DIR"
)

extra_xrun_args=()
sdf_xrun_args=(
  -define FA_GATE_ENABLE_SDF
  -notimingchecks
)
zero_delay_args=(
  -define FUNCTIONAL
  -delay_mode zero
  -notimingchecks
)

case "$CASE" in
  smoke)
    tb=tb_fa_top_axi_lite_smoke
    tb_file="tb/tb_fa_top_axi_lite_smoke.sv"
    extra_xrun_args=("${zero_delay_args[@]}")
    ;;
  zero)
    tb=tb_fa_top_zero_s256
    tb_file="tb/tb_fa_top_zero_s256.sv"
    extra_xrun_args=("${zero_delay_args[@]}" -define FA_GATE_DIAG)
    ;;
  zero_trace)
    tb=tb_fa_top_zero_s256
    tb_file="tb/tb_fa_top_zero_s256.sv"
    extra_xrun_args=("${zero_delay_args[@]}" -define FA_GATE_DIAG -define FA_GATE_TRACE)
    ;;
  zero_xtrace|zero_wrtrace)
    tb=tb_fa_top_zero_s256
    tb_file="tb/tb_fa_top_zero_s256.sv"
    extra_xrun_args=("${zero_delay_args[@]}" -define FA_GATE_DIAG -define FA_GATE_TRACE -define FA_GATE_XTRACE -define FA_GATE_XSTOP)
    ;;
  power_s256)
    tb=tb_fa_top_power_s256
    tb_file="tb/tb_fa_top_power_s256.sv"
    POWER_ACTIVITY_DIR=${POWER_ACTIVITY_DIR:-"$OUT_ROOT/power/out/activity"}
    POWER_VCD=${POWER_VCD:-"$POWER_ACTIVITY_DIR/fa_top_power_s256.vcd"}
    mkdir -p "$POWER_ACTIVITY_DIR"
    extra_xrun_args=("${zero_delay_args[@]}" -define FA_GATE_DIAG -define FA_POWER_VCD "+POWER_VCD=$POWER_VCD")
    ;;
  sdf_smoke)
    tb=tb_fa_top_axi_lite_smoke
    tb_file="tb/tb_fa_top_axi_lite_smoke.sv"
    extra_xrun_args=(-f "filelists/fa_top_gate_sdf.f" "${sdf_xrun_args[@]}")
    ;;
  sdf_s256|sdf_zero)
    tb=tb_fa_top_zero_s256
    tb_file="tb/tb_fa_top_zero_s256.sv"
    extra_xrun_args=(-f "filelists/fa_top_gate_sdf.f" "${sdf_xrun_args[@]}" -define FA_GATE_DIAG)
    ;;
  sdf_s256_trace|sdf_zero_trace)
    tb=tb_fa_top_zero_s256
    tb_file="tb/tb_fa_top_zero_s256.sv"
    extra_xrun_args=(-f "filelists/fa_top_gate_sdf.f" "${sdf_xrun_args[@]}" -define FA_GATE_DIAG -define FA_GATE_TRACE)
    ;;
  scoreboard)
    tb=tb_fa_top_s256_scoreboard
    tb_file="tb/tb_fa_top_s256_scoreboard.sv"
    extra_xrun_args=("${zero_delay_args[@]}" -define FA_GATE_DIAG)
    ;;
  scoreboard_trace)
    tb=tb_fa_top_s256_scoreboard
    tb_file="tb/tb_fa_top_s256_scoreboard.sv"
    extra_xrun_args=("${zero_delay_args[@]}" -define FA_GATE_DIAG -define FA_GATE_TRACE)
    ;;
  *)
    echo "usage: $0 [smoke|zero|zero_trace|zero_xtrace|zero_wrtrace|power_s256|sdf_smoke|sdf_s256|sdf_s256_trace|scoreboard|scoreboard_trace]" >&2
    exit 2
    ;;
esac

if [[ "$CASE" != sdf_* ]]; then
  extra_xrun_args=(-f "filelists/fa_top_gate.f" "${extra_xrun_args[@]}")
fi

"$XRUN" "${common_xrun_args[@]}" "${extra_xrun_args[@]}" "$tb_file" -top "$tb" -l "$RUN_DIR/xrun.log"
