#!/usr/bin/env bash
set -euo pipefail

script_path="${BASH_SOURCE[0]:-$0}"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
project_root="${GENUS_PROJECT_ROOT:-$script_dir}"
workspace_dir="${GENUS_WORKSPACE_DIR:-$project_root/workspace}"
results_dir="${GENUS_RESULTS_DIR:-$project_root/results}"
syn_script="${GENUS_SYN_SCRIPT:-$project_root/SYN/run_fa_accel_sky130_sram.tcl}"

export GENUS_PROJECT_ROOT="$project_root"
export GENUS_WORKSPACE_DIR="$workspace_dir"
export GENUS_RESULTS_DIR="$results_dir"

cd "$project_root"

if [[ ! -f "$syn_script" ]]; then
  echo "ERROR: Genus Tcl script not found: $syn_script" >&2
  exit 1
fi
if [[ ! -d "$workspace_dir" ]]; then
  echo "ERROR: workspace directory not found: $workspace_dir" >&2
  exit 1
fi

mkdir -p "$results_dir/logs"
log="$results_dir/logs/genus_$(date +%Y%m%d_%H%M%S).log"
genus_bin="${GENUS_BIN:-genus}"

export Genus_CPU_LIMIT=8

echo "INFO: project root: $project_root"
echo "INFO: workspace:    $workspace_dir"
echo "INFO: results:      $results_dir"
echo "INFO: Genus Tcl:    $syn_script"
echo "INFO: Genus CPU limit: $Genus_CPU_LIMIT"
echo "INFO: writing Genus log to $log"
"$genus_bin" -batch -files "$syn_script" 2>&1 | tee "$log"
