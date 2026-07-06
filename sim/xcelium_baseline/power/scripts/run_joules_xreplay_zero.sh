#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
POWER_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BASE_DIR=$(cd "$POWER_DIR/.." && pwd)

JOULES=${JOULES:-joules}
XRUN=${XRUN:-xrun}

export JOULES_OUT_DIR=${JOULES_OUT_DIR:-"$POWER_DIR/out/joules_xreplay_zero"}
export JOULES_MAPPING_FILE=${JOULES_MAPPING_FILE:-"$POWER_DIR/mapping/fa_top_genus_mapping.rpt"}
export JOULES_RTL_STIM=${JOULES_RTL_STIM:-"$POWER_DIR/rtl_wave/fa_top_power_s256_rtl.shm"}
export JOULES_RTL_STIM_FORMAT=${JOULES_RTL_STIM_FORMAT:-shm}
export JOULES_XRUN_PATH=${JOULES_XRUN_PATH:-$(command -v "$XRUN" 2>/dev/null || true)}

if ! command -v "$JOULES" >/dev/null 2>&1; then
  echo "ERROR: Joules command '$JOULES' was not found in PATH." >&2
  echo "Load Joules first, or set JOULES=/full/path/to/joules." >&2
  exit 127
fi

if [[ -z "$JOULES_XRUN_PATH" || ! -x "$JOULES_XRUN_PATH" ]]; then
  echo "ERROR: xrun executable not found for Xreplay." >&2
  echo "Load Xcelium first, or set JOULES_XRUN_PATH=/full/path/to/xrun." >&2
  exit 127
fi

if [[ ! -f "$JOULES_MAPPING_FILE" ]]; then
  echo "ERROR: missing Genus RTL-to-gate mapping file: $JOULES_MAPPING_FILE" >&2
  echo "Regenerate fa_top_mapped.v and export the matching mapping file from the same Genus run." >&2
  exit 2
fi

if [[ "$JOULES_RTL_STIM_FORMAT" == "vcd" && ! -f "$JOULES_RTL_STIM" && -f "${JOULES_RTL_STIM}.gz" ]]; then
  gzip -dk "${JOULES_RTL_STIM}.gz"
fi

if [[ ! -e "$JOULES_RTL_STIM" ]]; then
  echo "ERROR: missing RTL stimulus waveform: $JOULES_RTL_STIM" >&2
  echo "Run power/scripts/run_rtl_power_activity.sh first, or set JOULES_RTL_STIM." >&2
  exit 2
fi

mkdir -p "$JOULES_OUT_DIR"
cd "$BASE_DIR"
"$JOULES" -files "power/tcl/run_fa_top_xreplay_zero.tcl" -log "$JOULES_OUT_DIR/joules_xreplay_zero.log"
