#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
POWER_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BASE_DIR=$(cd "$POWER_DIR/.." && pwd)
REPO_ROOT=$(cd "$BASE_DIR/../.." && pwd)

XRUN=${XRUN:-xrun}
RTL_WAVE_FORMAT=${RTL_WAVE_FORMAT:-shm}
RUN_DIR=${RUN_DIR:-"$POWER_DIR/logs/rtl_power_s256"}
WORK_DIR=${WORK_DIR:-"$POWER_DIR/out/build/rtl_power_s256"}

if [[ -n "${RTL_DIR:-}" ]]; then
  RTL_ROOT="$RTL_DIR"
elif [[ -d "$REPO_ROOT/workspace/RTL" ]]; then
  RTL_ROOT="$REPO_ROOT/workspace/RTL"
elif [[ -d "$POWER_DIR/rtl" ]]; then
  RTL_ROOT="$POWER_DIR/rtl"
else
  echo "ERROR: RTL directory not found." >&2
  echo "Set RTL_DIR=/path/to/the/fa_top/RTL snapshot used by Genus." >&2
  exit 2
fi

if ! command -v "$XRUN" >/dev/null 2>&1; then
  echo "ERROR: Xcelium command '$XRUN' was not found in PATH." >&2
  echo "Load Xcelium first, or set XRUN=/full/path/to/xrun." >&2
  exit 127
fi

rtl_sources=(
  sky130_sram_0kbytes_1rw1r_64x32_8.v
  sky130_sram_0kbytes_1rw1r_64x64_8.v
  sky130_sram_0kbytes_1rw1r_128x16_16.v
  sky130_sram_0kbytes_1rw1r_64x32_8_wrapper.v
  sky130_sram_0kbytes_1rw1r_64x64_8_wrapper.v
  sky130_sram_0kbytes_1rw1r_128x16_16_timed_wrapper.v
  qk_sram_cluster.v
  v_sram_cluster.v
  acc_sram_cluster.v
  meta_sram_cluster.v
  dot_frontend.v
  score_exp_banked_rom.v
  score_exp_pipe.v
  update_token_fifo.v
  update_state_cluster.v
  packed_compute_core.v
  axi_lite_regs.v
  perf_counters.v
  task_ctrl.v
  dma_cmd_queue.v
  dma_read_master.v
  dma_write_master.v
  dma_engine.v
  q_load_store_adapter.v
  k_load_adapter.v
  v_load_adapter.v
  o_store_adapter.v
  page_manager.v
  score_scheduler.v
  reciprocal_approx.v
  output_norm_pipe.v
  finalize_cluster.v
  fa_top.v
)

src_args=()
for src in "${rtl_sources[@]}"; do
  path="$RTL_ROOT/$src"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: missing RTL source: $path" >&2
    exit 2
  fi
  src_args+=("$path")
done

mkdir -p "$RUN_DIR" "$WORK_DIR" "$POWER_DIR/rtl_wave"
cd "$BASE_DIR"

common_args=(
  -64bit
  -sv
  -timescale 1ns/1ps
  -access +rwc
  -define FUNCTIONAL
  "models/axi_mem_model_128.sv"
  "${src_args[@]}"
  "tb/tb_fa_top_power_s256.sv"
  -top tb_fa_top_power_s256
  -xmlibdirname "$WORK_DIR"
)

case "$RTL_WAVE_FORMAT" in
  shm)
    export RTL_POWER_SHM=${RTL_POWER_SHM:-"$POWER_DIR/rtl_wave/fa_top_power_s256_rtl.shm"}
    "$XRUN" "${common_args[@]}" -input "power/tcl/run_rtl_power_activity.tcl" -l "$RUN_DIR/xrun_rtl_power.log"
    echo "INFO: RTL SHM waveform: $RTL_POWER_SHM"
    ;;
  vcd)
    export POWER_VCD=${POWER_VCD:-"$POWER_DIR/rtl_wave/fa_top_power_s256_rtl.vcd"}
    "$XRUN" "${common_args[@]}" -define FA_POWER_VCD "+POWER_VCD=$POWER_VCD" -input "tcl/run_gate_func.tcl" -l "$RUN_DIR/xrun_rtl_power.log"
    if command -v gzip >/dev/null 2>&1 && [[ -f "$POWER_VCD" ]]; then
      gzip -f "$POWER_VCD"
      echo "INFO: RTL VCD waveform: ${POWER_VCD}.gz"
    else
      echo "INFO: RTL VCD waveform: $POWER_VCD"
    fi
    ;;
  *)
    echo "ERROR: unsupported RTL_WAVE_FORMAT=$RTL_WAVE_FORMAT; use shm or vcd." >&2
    exit 2
    ;;
esac

echo "INFO: xrun log: $RUN_DIR/xrun_rtl_power.log"
