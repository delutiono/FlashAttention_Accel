#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$BASE_DIR/../.." && pwd)

XRUN=${XRUN:-xrun}
RUN_DIR=${RUN_DIR:-"$REPO_ROOT/artifacts/runs/xcelium_baseline_axi_mem_model_test"}
WORK_DIR=${WORK_DIR:-"$REPO_ROOT/build/xcelium_baseline/axi_mem_model_test"}

mkdir -p "$RUN_DIR" "$WORK_DIR"

if ! command -v "$XRUN" >/dev/null 2>&1; then
  echo "ERROR: Xcelium command '$XRUN' was not found in PATH." >&2
  echo "Load your Cadence/Xcelium environment first, or set XRUN=/full/path/to/xrun." >&2
  exit 127
fi

cd "$REPO_ROOT"

run_case() {
  local name=$1
  local tb_file=$2
  local top=$3
  local case_run_dir="$RUN_DIR/$name"
  local case_work_dir="$WORK_DIR/$name"

  mkdir -p "$case_run_dir" "$case_work_dir"

  "$XRUN" \
    -64bit \
    -sv \
    -timescale 1ns/1ps \
    -access +rwc \
    -define FA_GATE_TRACE \
    "$BASE_DIR/models/axi_mem_model_128.sv" \
    "$tb_file" \
    -top "$top" \
    -input "$BASE_DIR/tcl/run_gate_func.tcl" \
    -xmlibdirname "$case_work_dir" \
    -l "$case_run_dir/xrun.log"
}

run_case \
  two_bursts \
  "$BASE_DIR/tests/tb_axi_mem_model_write_two_bursts.sv" \
  tb_axi_mem_model_write_two_bursts

run_case \
  bready_pulse_skew \
  "$BASE_DIR/tests/tb_axi_mem_model_bready_pulse_skew.sv" \
  tb_axi_mem_model_bready_pulse_skew

echo "PASS: AXI memory model sanity checks completed"
