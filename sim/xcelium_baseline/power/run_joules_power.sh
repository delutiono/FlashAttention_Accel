#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

JOULES=${JOULES:-joules}
ACTIVITY_DIR=${POWER_ACTIVITY_DIR:-"$BASE_DIR/power/out/activity"}
export JOULES_ACTIVITY_FILE=${JOULES_ACTIVITY_FILE:-"$ACTIVITY_DIR/fa_top_power_s256.vcd"}
export JOULES_OUT_DIR=${JOULES_OUT_DIR:-"$BASE_DIR/power/out/joules"}

if ! command -v "$JOULES" >/dev/null 2>&1; then
  echo "ERROR: Joules command '$JOULES' was not found in PATH." >&2
  echo "Load your Cadence/Joules environment first, or set JOULES=/full/path/to/joules." >&2
  exit 127
fi

if [[ ! -f "$JOULES_ACTIVITY_FILE" && -f "${JOULES_ACTIVITY_FILE}.gz" ]]; then
  gzip -dk "${JOULES_ACTIVITY_FILE}.gz"
fi

mkdir -p "$JOULES_OUT_DIR"
cd "$BASE_DIR"
"$JOULES" -files "power/tcl/run_fa_top_power.tcl" -log "$JOULES_OUT_DIR/joules.log"
