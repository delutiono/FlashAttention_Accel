param(
  [string]$PatchRoot = "artifacts/genus_patches",
  [string]$PatchName = "",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-LinesUtf8 {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [AllowEmptyString()][AllowEmptyCollection()][string[]]$Lines
  )
  $parent = Split-Path -Parent $Path
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), $encoding)
}

function Convert-ToUnixPath {
  param([string]$Path)
  return $Path.Replace("\", "/")
}

function Remove-TreeWithRetry {
  param([Parameter(Mandatory = $true)][string]$Path)

  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Remove-Item -LiteralPath $Path -Recurse -Force
      return
    } catch {
      if ($attempt -eq 3) {
        throw
      }
      [System.GC]::Collect()
      [System.GC]::WaitForPendingFinalizers()
      Start-Sleep -Milliseconds (200 * $attempt)
    }
  }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

if ([string]::IsNullOrWhiteSpace($PatchName)) {
  $PatchName = "genus_bs1_patch_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss")
}

$patchRootAbs = Join-Path $repoRoot $PatchRoot
$patchDir = Join-Path $patchRootAbs $PatchName
$synDir = Join-Path $patchDir "SYN"
$rtlDir = Join-Path $patchDir "workspace/RTL"
$constraintDir = Join-Path $patchDir "workspace/constraints"
$filelistDir = Join-Path $patchDir "workspace/filelists"

if (Test-Path -LiteralPath $patchDir) {
  if (-not $Force) {
    throw "Patch directory already exists: $patchDir. Use -Force to replace it."
  }
  Remove-Item -LiteralPath $patchDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $synDir, $rtlDir, $constraintDir, $filelistDir | Out-Null

$runScript = @(
  '#!/usr/bin/env bash',
  'set -euo pipefail',
  '',
  'script_path="${BASH_SOURCE[0]:-$0}"',
  'script_dir="$(cd "$(dirname "$script_path")" && pwd)"',
  'project_root="${GENUS_PROJECT_ROOT:-$script_dir}"',
  'workspace_dir="${GENUS_WORKSPACE_DIR:-$project_root/workspace}"',
  'results_dir="${GENUS_RESULTS_DIR:-$project_root/results}"',
  'syn_script="${GENUS_SYN_SCRIPT:-$project_root/SYN/run_fa_accel_sky130_sram.tcl}"',
  '',
  'export GENUS_PROJECT_ROOT="$project_root"',
  'export GENUS_WORKSPACE_DIR="$workspace_dir"',
  'export GENUS_RESULTS_DIR="$results_dir"',
  'export GENUS_THREADS="${GENUS_THREADS:-8}"',
  '',
  'cd "$project_root"',
  '',
  'if [[ ! -f "$syn_script" ]]; then',
  '  echo "ERROR: Genus Tcl script not found: $syn_script" >&2',
  '  exit 1',
  'fi',
  'if [[ ! -d "$workspace_dir" ]]; then',
  '  echo "ERROR: workspace directory not found: $workspace_dir" >&2',
  '  exit 1',
  'fi',
  '',
  'mkdir -p "$results_dir/logs"',
  'log="$results_dir/logs/genus_$(date +%Y%m%d_%H%M%S).log"',
  'genus_bin="${GENUS_BIN:-genus}"',
  '',
  'echo "INFO: project root: $project_root"',
  'echo "INFO: workspace:    $workspace_dir"',
  'echo "INFO: results:      $results_dir"',
  'echo "INFO: Genus Tcl:    $syn_script"',
  'echo "INFO: GENUS_PHYSICAL=${GENUS_PHYSICAL:-1}"',
  'echo "INFO: GENUS_DEF_FILE=${GENUS_DEF_FILE:-<unset>}"',
  'echo "INFO: GENUS_PREDICT_FLOORPLAN=${GENUS_PREDICT_FLOORPLAN:-1}"',
  'echo "INFO: GENUS_ALLOW_PHYSICAL_FALLBACK=${GENUS_ALLOW_PHYSICAL_FALLBACK:-0}"',
  'echo "INFO: GENUS_CAP_TABLE=${GENUS_CAP_TABLE:-<unset>}"',
  'echo "INFO: GENUS_THREADS=$GENUS_THREADS"',
  'echo "INFO: writing Genus log to $log"',
  '"$genus_bin" -batch -files "$syn_script" 2>&1 | tee "$log"'
)
Write-LinesUtf8 -Path (Join-Path $patchDir "run_genus.sh") -Lines $runScript

Copy-Item `
  -LiteralPath (Join-Path $repoRoot "synth/run_fa_accel_sky130_sram.tcl") `
  -Destination (Join-Path $synDir "run_fa_accel_sky130_sram.tcl") `
  -Force

Copy-Item `
  -LiteralPath (Join-Path $repoRoot "synth/constraints.sdc") `
  -Destination (Join-Path $constraintDir "timing_300m.sdc") `
  -Force

$rtlPatchFiles = @(
  "fa_pkg.sv",
  "fa_regfile.sv",
  "fa_q_buffer.sv",
  "fa_kv_buffer.sv",
  "fa_group_engine.sv",
  "fa_o_group_store.sv",
  "fa_accel_top.sv",
  "fa_sram_macros.v"
)
foreach ($rtlName in $rtlPatchFiles) {
  Copy-Item `
    -LiteralPath (Join-Path $repoRoot "rtl/$rtlName") `
    -Destination (Join-Path $rtlDir $rtlName) `
    -Force
}

$sramBlackbox = @(
  '`timescale 1ns/1ps',
  '`default_nettype none',
  '',
  'module sky130_sram_0kbytes_1rw1r_32x64_8 (',
  '`ifdef USE_POWER_PINS',
  '  inout wire vccd1,',
  '  inout wire vssd1,',
  '`endif',
  '  input  wire                  clk0,',
  '  input  wire                  csb0,',
  '  input  wire                  web0,',
  '  input  wire [3:0]            wmask0,',
  '  input  wire                  spare_wen0,',
  '  input  wire [5:0]            addr0,',
  '  input  wire [32:0]           din0,',
  '  output wire [32:0]           dout0,',
  '  input  wire                  clk1,',
  '  input  wire                  csb1,',
  '  input  wire [5:0]            addr1,',
  '  output wire [32:0]           dout1',
  ');',
  'endmodule',
  '',
  'module sky130_sram_0kbytes_1rw1r_48x16_8 (',
  '`ifdef USE_POWER_PINS',
  '  inout wire vccd1,',
  '  inout wire vssd1,',
  '`endif',
  '  input  wire                  clk0,',
  '  input  wire                  csb0,',
  '  input  wire                  web0,',
  '  input  wire [5:0]            wmask0,',
  '  input  wire                  spare_wen0,',
  '  input  wire [3:0]            addr0,',
  '  input  wire [48:0]           din0,',
  '  output wire [48:0]           dout0,',
  '  input  wire                  clk1,',
  '  input  wire                  csb1,',
  '  input  wire [3:0]            addr1,',
  '  output wire [48:0]           dout1',
  ');',
  'endmodule',
  '',
  '`default_nettype wire'
)
Write-LinesUtf8 -Path (Join-Path $rtlDir "sky130_sram_macro_blackboxes.v") -Lines $sramBlackbox

$rtlFilelistLines = New-Object System.Collections.Generic.List[string]
$rtlSourceList = Get-Content -LiteralPath (Join-Path $repoRoot "synth/filelist.f") |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }
foreach ($rel in $rtlSourceList) {
  $leaf = Split-Path -Leaf $rel
  if ($leaf -eq "fa_q_buffer.sv") {
    $rtlFilelistLines.Add("../RTL/sky130_sram_macro_blackboxes.v")
    $rtlFilelistLines.Add("../RTL/fa_sram_macros.v")
  }
  $rtlFilelistLines.Add("../RTL/$leaf")
}
Write-LinesUtf8 -Path (Join-Path $filelistDir "rtl.f") -Lines $rtlFilelistLines.ToArray()

$readme = @(
  '# Genus BS1 Incremental Patch',
  '',
  'Included replacement files:',
  '',
  '- `run_genus.sh`',
  '- `SYN/run_fa_accel_sky130_sram.tcl`',
  '- `workspace/constraints/timing_300m.sdc`',
  '- `workspace/filelists/rtl.f`',
  '- `workspace/RTL/fa_pkg.sv`',
  '- `workspace/RTL/fa_accel_top.sv`',
  '- `workspace/RTL/fa_regfile.sv`',
  '- `workspace/RTL/fa_q_buffer.sv`',
  '- `workspace/RTL/fa_kv_buffer.sv`',
  '- `workspace/RTL/fa_group_engine.sv`',
  '- `workspace/RTL/fa_o_group_store.sv`',
  '- `workspace/RTL/fa_sram_macros.v`',
  '- `workspace/RTL/sky130_sram_macro_blackboxes.v`',
  '',
  'Unzip this archive inside the existing remote project root:',
  '',
  '```bash',
  'cd /home/liuqisong/Desktop/genus_bs1',
  'unzip -o genus_bs1_patch.zip',
  'bash run_genus.sh',
  '```',
  '',
  'Physical-aware synthesis defaults:',
  '',
  '- `GENUS_PHYSICAL=1` enables physical-aware synthesis.',
  '- `GENUS_PREDICT_FLOORPLAN=1` asks Genus to run `predict_floorplan` when `GENUS_DEF_FILE` is not set.',
  '- `GENUS_ALLOW_PHYSICAL_FALLBACK=0` makes missing/failed floorplan setup a hard error instead of silently falling back to logical synthesis.',
  '- `GENUS_DEF_FILE=/path/to/seed.def` can reuse a prior or Innovus-exported floorplan.',
  '- `GENUS_CAP_TABLE=/path/to/cap.tbl` is optional but recommended for better pre-route RC accuracy.',
  '- `GENUS_THREADS=8` is the default multi-CPU request; increase it only if the remote license/server load allows.',
  '',
  'This patch intentionally excludes Liberty, LEF, SRAM macro payloads, and previous results.'
)
Write-LinesUtf8 -Path (Join-Path $patchDir "README_PATCH.md") -Lines $readme

$zipPath = Join-Path $patchRootAbs ($PatchName + ".zip")
if (Test-Path -LiteralPath $zipPath) {
  if (-not $Force) {
    throw "Patch archive already exists: $zipPath. Use -Force to replace it."
  }
  Remove-TreeWithRetry -Path $zipPath
}

Compress-Archive -Path (Join-Path $patchDir "*") -DestinationPath $zipPath -Force
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
  throw "Patch archive was not created: $zipPath"
}
try {
  Remove-TreeWithRetry -Path $patchDir
} catch {
  Write-Warning "Patch archive was created, but temporary directory cleanup failed: $_"
  Write-Warning "Temporary directory may be removed manually: $patchDir"
}

Write-Host "Patch archive: $(Convert-ToUnixPath $zipPath)"
