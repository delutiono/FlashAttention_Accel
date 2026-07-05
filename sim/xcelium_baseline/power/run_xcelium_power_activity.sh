#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_ROOT="$BASE_DIR"

ACTIVITY_DIR=${POWER_ACTIVITY_DIR:-"$OUT_ROOT/power/out/activity"}
LOG_DIR=${POWER_LOG_DIR:-"$OUT_ROOT/power/out/logs"}
mkdir -p "$ACTIVITY_DIR" "$LOG_DIR"

export POWER_ACTIVITY_DIR="$ACTIVITY_DIR"
export POWER_VCD=${POWER_VCD:-"$ACTIVITY_DIR/fa_top_power_s256.vcd"}
export RUN_DIR=${RUN_DIR:-"$LOG_DIR/xcelium_power_s256"}
export WORK_DIR=${WORK_DIR:-"$OUT_ROOT/build/xcelium_baseline/fa_top_power_s256"}

bash "$BASE_DIR/run_xcelium.sh" power_s256

if command -v gzip >/dev/null 2>&1 && [[ -f "$POWER_VCD" ]]; then
  gzip -f "$POWER_VCD"
  echo "INFO: compressed power VCD: ${POWER_VCD}.gz"
else
  echo "INFO: power VCD: $POWER_VCD"
fi

echo "INFO: xrun log: $RUN_DIR/xrun.log"
