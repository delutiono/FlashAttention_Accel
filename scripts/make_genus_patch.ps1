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

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

if ([string]::IsNullOrWhiteSpace($PatchName)) {
  $PatchName = "genus_bs1_patch_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss")
}

$patchRootAbs = Join-Path $repoRoot $PatchRoot
$patchDir = Join-Path $patchRootAbs $PatchName
$synDir = Join-Path $patchDir "SYN"
$rtlDir = Join-Path $patchDir "workspace/RTL"

if (Test-Path -LiteralPath $patchDir) {
  if (-not $Force) {
    throw "Patch directory already exists: $patchDir. Use -Force to replace it."
  }
  Remove-Item -LiteralPath $patchDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $synDir, $rtlDir | Out-Null

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
  'echo "INFO: writing Genus log to $log"',
  '"$genus_bin" -batch -files "$syn_script" 2>&1 | tee "$log"'
)
Write-LinesUtf8 -Path (Join-Path $patchDir "run_genus.sh") -Lines $runScript

Copy-Item `
  -LiteralPath (Join-Path $repoRoot "synth/run_fa_accel_sky130_sram.tcl") `
  -Destination (Join-Path $synDir "run_fa_accel_sky130_sram.tcl") `
  -Force

Copy-Item `
  -LiteralPath (Join-Path $repoRoot "rtl/fa_regfile.sv") `
  -Destination (Join-Path $rtlDir "fa_regfile.sv") `
  -Force

Copy-Item `
  -LiteralPath (Join-Path $repoRoot "rtl/fa_sram_macros.v") `
  -Destination (Join-Path $patchDir "workspace/RTL/fa_sram_macros.v") `
  -Force

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

$readme = @(
  '# Genus BS1 Incremental Patch',
  '',
  'Included replacement files:',
  '',
  '- `run_genus.sh`',
  '- `SYN/run_fa_accel_sky130_sram.tcl`',
  '- `workspace/RTL/fa_regfile.sv`',
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
  'This patch intentionally excludes Liberty, LEF, SRAM macro payloads, and previous results.'
)
Write-LinesUtf8 -Path (Join-Path $patchDir "README_PATCH.md") -Lines $readme

$zipPath = Join-Path $patchRootAbs ($PatchName + ".zip")
if (Test-Path -LiteralPath $zipPath) {
  if (-not $Force) {
    throw "Patch archive already exists: $zipPath. Use -Force to replace it."
  }
  Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path $patchDir "*") -DestinationPath $zipPath -Force
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
  throw "Patch archive was not created: $zipPath"
}
Remove-Item -LiteralPath $patchDir -Recurse -Force

Write-Host "Patch archive: $(Convert-ToUnixPath $zipPath)"
