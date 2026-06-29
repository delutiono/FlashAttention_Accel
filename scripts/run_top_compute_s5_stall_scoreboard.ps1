param(
  [string]$WorkLib = "work_top_compute_s5_stall_scoreboard",
  [string]$BuildDir = "build/top_compute_s5_stall",
  [string]$DumpFile = "o_beats64.hex",
  [string]$SummaryFile = "summary.json",
  [int]$ArReadyStallCycles = 1,
  [int]$AwReadyStallCycles = 1,
  [int]$WReadyStallCycles = 1,
  [int]$RValidDelayCycles = 1,
  [int]$BValidDelayCycles = 1
)

$ErrorActionPreference = "Stop"

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Exe,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
  )

  Write-Host ">> $Exe $($Args -join ' ')"
  & $Exe @Args
  if ($LASTEXITCODE -ne 0) {
    throw "$Exe failed with exit code $LASTEXITCODE"
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$dumpPath = Join-Path $BuildDir $DumpFile
$summaryPath = Join-Path $BuildDir $SummaryFile

if (Test-Path $dumpPath) {
  Remove-Item $dumpPath
}
if (Test-Path $summaryPath) {
  Remove-Item $summaryPath
}

Invoke-Checked vlib $WorkLib
Invoke-Checked vlog "-sv" "-work" $WorkLib "-f" "rtl/filelist.f" "sim/axi_mem_model.sv" "sim/tb_top_compute_s5_tile_smoke.sv"
Invoke-Checked vsim "-c" "-lib" $WorkLib `
  "-gAXI_MEM_AR_READY_STALL_CYCLES=$ArReadyStallCycles" `
  "-gAXI_MEM_AW_READY_STALL_CYCLES=$AwReadyStallCycles" `
  "-gAXI_MEM_W_READY_STALL_CYCLES=$WReadyStallCycles" `
  "-gAXI_MEM_R_VALID_DELAY_CYCLES=$RValidDelayCycles" `
  "-gAXI_MEM_B_VALID_DELAY_CYCLES=$BValidDelayCycles" `
  "tb_top_compute_s5_tile_smoke" `
  "+DUMP_O_BEATS64=$dumpPath" `
  "-do" "run -all; quit -f"
Invoke-Checked python "-B" "scripts/compare_vector_output.py" `
  "--metadata" "test_vectors/generated/s5_d64_seed101/s5_d64_seed101_metadata.json" `
  "--dut-hex" $dumpPath `
  "--format" "beats64" `
  "--require-mae" "0" `
  "--require-maxae" "0" `
  "--dump-summary-json" $summaryPath

Write-Host "DUT O beats64 dump: $dumpPath"
Write-Host "Scoreboard summary: $summaryPath"
