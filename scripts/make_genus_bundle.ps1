param(
  [string]$BundleRoot = "artifacts/genus_bundles",
  [string]$BundleName = "",
  [switch]$NoArchive,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Resolve-Path -LiteralPath (Join-Path $repoRoot $Path)).Path
}

function Copy-RequiredFile {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$DestinationDir
  )
  if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "Required file is missing: $Source"
  }
  New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
  Copy-Item -LiteralPath $Source -Destination $DestinationDir -Force
  return (Join-Path $DestinationDir (Split-Path -Leaf $Source))
}

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

if ([string]::IsNullOrWhiteSpace($BundleName)) {
  $BundleName = "fa_accel_genus_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss")
}

$bundleRootAbs = Join-Path $repoRoot $BundleRoot
$bundleDir = Join-Path $bundleRootAbs $BundleName
$workspaceDir = Join-Path $bundleDir "workspace"
$synDir = Join-Path $bundleDir "SYN"
$resultsDir = Join-Path $bundleDir "results"
$rtlDir = Join-Path $workspaceDir "RTL"
$constraintDir = Join-Path $workspaceDir "constraints"
$libsDir = Join-Path $workspaceDir "LIBS"
$lefsDir = Join-Path $workspaceDir "LEFS"
$verilogDir = Join-Path $workspaceDir "VERILOG"
$filelistDir = Join-Path $workspaceDir "filelists"

if (Test-Path -LiteralPath $bundleDir) {
  if (-not $Force) {
    throw "Bundle directory already exists: $bundleDir. Use -Force to replace it."
  }
  Remove-Item -LiteralPath $bundleDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $rtlDir, $constraintDir, $libsDir, $lefsDir, $verilogDir, $filelistDir, $synDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $resultsDir "reports"), (Join-Path $resultsDir "outputs"), (Join-Path $resultsDir "logs") | Out-Null

$rtlListPath = Resolve-RepoPath "synth/filelist.f"
$rtlRelPaths = Get-Content -LiteralPath $rtlListPath |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }

$resolvedRtl = New-Object System.Collections.Generic.List[string]
foreach ($rel in $rtlRelPaths) {
  $resolved = (Resolve-Path -LiteralPath (Join-Path (Split-Path -Parent $rtlListPath) $rel)).Path
  $resolvedRtl.Add($resolved)
}

$sramWrapper = Resolve-RepoPath "rtl/fa_sram_macros.v"
if (-not $resolvedRtl.Contains($sramWrapper)) {
  $qBuffer = Resolve-RepoPath "rtl/fa_q_buffer.sv"
  $qIndex = $resolvedRtl.IndexOf($qBuffer)
  if ($qIndex -lt 0) {
    $resolvedRtl.Add($sramWrapper)
  } else {
    $resolvedRtl.Insert($qIndex, $sramWrapper)
  }
}

$sramBlackboxName = "sky130_sram_macro_blackboxes.v"
$sramBlackboxPath = Join-Path $rtlDir $sramBlackboxName
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
Write-LinesUtf8 -Path $sramBlackboxPath -Lines $sramBlackbox

$rtlFilelistLines = New-Object System.Collections.Generic.List[string]
foreach ($src in $resolvedRtl) {
  if ($src -eq $sramWrapper) {
    $rtlFilelistLines.Add("../RTL/$sramBlackboxName")
  }
  $copied = Copy-RequiredFile -Source $src -DestinationDir $rtlDir
  $rtlFilelistLines.Add("../RTL/{0}" -f (Split-Path -Leaf $copied))
}
Write-LinesUtf8 -Path (Join-Path $filelistDir "rtl.f") -Lines $rtlFilelistLines.ToArray()

$sramMacroSources = @(
  (Resolve-RepoPath "sky130A/libs.ref/sky130_sram_macros/verilog/sky130_sram_0kbytes_1rw1r_32x64_8.v")
)
$sramMacroFilelist = foreach ($src in $sramMacroSources) {
  $copied = Copy-RequiredFile -Source $src -DestinationDir $rtlDir
  "../RTL/{0}" -f (Split-Path -Leaf $copied)
}
Write-LinesUtf8 -Path (Join-Path $filelistDir "sram_macro_verilog.f") -Lines $sramMacroFilelist

$libSources = @(
  (Resolve-RepoPath "sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib"),
  (Resolve-RepoPath "sky130A/libs.ref/sky130_sram_macros/lib/sky130_sram_0kbytes_1rw1r_32x64_8_TT_1p8V_25C.lib")
)
$libFilelist = foreach ($src in $libSources) {
  $copied = Copy-RequiredFile -Source $src -DestinationDir $libsDir
  "../LIBS/{0}" -f (Split-Path -Leaf $copied)
}
Write-LinesUtf8 -Path (Join-Path $filelistDir "libs_tt.f") -Lines $libFilelist

$lefSources = @(
  (Resolve-RepoPath "sky130A/libs.ref/sky130_fd_sc_hs/techlef/sky130_fd_sc_hs__nom.tlef"),
  (Resolve-RepoPath "sky130A/libs.ref/sky130_fd_sc_hs/lef/sky130_fd_sc_hs.lef"),
  (Resolve-RepoPath "sky130A/libs.ref/sky130_sram_macros/lef/sky130_sram_0kbytes_1rw1r_32x64_8.lef")
)
$lefFilelist = foreach ($src in $lefSources) {
  $copied = Copy-RequiredFile -Source $src -DestinationDir $lefsDir
  "../LEFS/{0}" -f (Split-Path -Leaf $copied)
}
Write-LinesUtf8 -Path (Join-Path $filelistDir "lefs.f") -Lines $lefFilelist

$stdCellVerilogSources = @(
  (Resolve-RepoPath "sky130A/libs.ref/sky130_fd_sc_hs/verilog/primitives.v"),
  (Resolve-RepoPath "sky130A/libs.ref/sky130_fd_sc_hs/verilog/sky130_fd_sc_hs.v")
)
$stdCellVerilogFilelist = foreach ($src in $stdCellVerilogSources) {
  $copied = Copy-RequiredFile -Source $src -DestinationDir $verilogDir
  "../VERILOG/{0}" -f (Split-Path -Leaf $copied)
}
Write-LinesUtf8 -Path (Join-Path $filelistDir "stdcell_verilog.f") -Lines $stdCellVerilogFilelist

Copy-Item -LiteralPath (Resolve-RepoPath "synth/constraints.sdc") -Destination (Join-Path $constraintDir "timing_300m.sdc") -Force
Copy-RequiredFile -Source (Resolve-RepoPath "synth/run_fa_accel_sky130_sram.tcl") -DestinationDir $synDir | Out-Null

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
Write-LinesUtf8 -Path (Join-Path $bundleDir "run_genus.sh") -Lines $runScript

$gitHead = "unknown"
$gitStatus = @()
try {
  $gitHead = (& git rev-parse --short HEAD).Trim()
  $gitStatus = & git status --short
} catch {
  $gitStatus = @("git status unavailable: $($_.Exception.Message)")
}

$manifest = @(
  "Bundle: $BundleName",
  "Created: $(Get-Date -Format s)",
  "Repo: $repoRoot",
  "Git HEAD: $gitHead",
  "",
  "Top: fa_accel_top",
  "RTL filelist: workspace/filelists/rtl.f",
  "Liberty filelist: workspace/filelists/libs_tt.f",
  "LEF filelist: workspace/filelists/lefs.f",
  "SRAM macro Verilog filelist: workspace/filelists/sram_macro_verilog.f",
  "SRAM synthesis blackboxes: workspace/RTL/$sramBlackboxName",
  "",
  "Git status at bundle time:"
) + $gitStatus
Write-LinesUtf8 -Path (Join-Path $bundleDir "MANIFEST.txt") -Lines $manifest

$readme = @(
  '# FA Accel Genus Bundle',
  '',
  'This bundle is self-contained for a first Cadence Genus run of the main RTL top `fa_accel_top`.',
  '',
  '## Directory Layout',
  '',
  '```text',
  'SYN/                         Genus Tcl',
  'workspace/RTL/               Main RTL, SRAM synthesis blackboxes, and SRAM macro Verilog payloads',
  'workspace/LIBS/              TT Liberty files for stdcell and selected SRAM macros',
  'workspace/LEFS/              Tech/cell/SRAM LEF files',
  'workspace/VERILOG/           Stdcell Verilog for later gate-level simulation reference',
  'workspace/constraints/       Timing SDC',
  'workspace/filelists/         Editable input file lists',
  'results/reports/             Genus reports',
  'results/outputs/             Mapped netlist and SDC',
  'results/logs/                Genus shell logs',
  '```',
  '',
  '## Run',
  '',
  '```bash',
  'unzip <uploaded-archive>.zip',
  "cd $BundleName",
  'bash run_genus.sh',
  '```',
  '',
  'For the remote directory shown in the current experiment, this is equivalent to:',
  '',
  '```bash',
  'cd /home/liuqisong/Desktop/genus_bs1',
  'bash run_genus.sh',
  '```',
  '',
  'If the remote server uses different PDK/library locations, edit the filelists under `workspace/filelists/` or override them:',
  '',
  '```bash',
  'export GENUS_PROJECT_ROOT=/home/liuqisong/Desktop/genus_bs1',
  'export LIB_FILELIST=/remote/path/libs_tt.f',
  'export LEF_FILELIST=/remote/path/lefs.f',
  'export RTL_FILELIST=/remote/path/rtl.f',
  'export SDC_FILE=/remote/path/timing_300m.sdc',
  'export GENUS_RESULTS_DIR=/remote/path/results',
  'bash run_genus.sh',
  '```',
  '',
  'By default `GENUS_PHYSICAL=1` now requires a usable physical floorplan before `syn_generic -physical`. Set `GENUS_DEF_FILE=/path/to/seed.def` to reuse a DEF, or leave `GENUS_PREDICT_FLOORPLAN=1` so Genus tries `predict_floorplan` and writes `results/outputs/fa_accel_top/fa_accel_top_predict_floorplan.def`.',
  '',
  'Set `GENUS_CAP_TABLE=/path/to/cap.tbl` when an RC/cap table is available. Set `GENUS_THREADS=8` or another server-appropriate value to request multi-CPU Genus/super-threading. Set `GENUS_ALLOW_PHYSICAL_FALLBACK=1` only for debug runs where falling back to logical `syn_generic/syn_map/syn_opt` is acceptable. Set `GENUS_PHYSICAL=0` to force logical synthesis.',
  '',
  'SRAM synthesis blackbox stubs are read by default. SRAM behavioral Verilog is included for reference, but the Tcl does not read it by default. The intended synthesis path resolves SRAM macro instances from Liberty. Set `READ_SRAM_BEHAV_RTL=1` only as a debug fallback.',
  '',
  '## Expected Outputs',
  '',
  '- `results/reports/fa_accel_top/area.rpt`',
  '- `results/reports/fa_accel_top/timing.rpt`',
  '- `results/reports/fa_accel_top/power.rpt`',
  '- `results/reports/fa_accel_top/qor_final.rpt`',
  '- `results/reports/fa_accel_top/sram_macro_instances.rpt`',
  '- `results/outputs/fa_accel_top/fa_accel_top_mapped.v`',
  '- `results/outputs/fa_accel_top/fa_accel_top_mapped.sdc`'
)
Write-LinesUtf8 -Path (Join-Path $bundleDir "README.md") -Lines $readme

$zipPath = "$bundleDir.zip"
if (Test-Path -LiteralPath $zipPath) {
  if (-not $Force) {
    throw "Archive already exists: $zipPath. Use -Force to replace it."
  }
  Remove-Item -LiteralPath $zipPath -Force
}

if (-not $NoArchive) {
  Compress-Archive -LiteralPath $bundleDir -DestinationPath $zipPath -Force
}

Write-Host "Bundle directory: $(Convert-ToUnixPath $bundleDir)"
if (-not $NoArchive) {
  Write-Host "Bundle archive:   $(Convert-ToUnixPath $zipPath)"
}
