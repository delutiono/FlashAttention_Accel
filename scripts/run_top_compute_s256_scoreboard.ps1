param(
  [string]$WorkLib = "work_top_compute_s256_scoreboard",
  [string]$VectorDir = "artifacts/vectors/s256_d64_seed100",
  [string]$RunDir = "artifacts/runs/s256_d64_seed100",
  [string]$CaseName = "s256_d64_seed100",
  [int]$Seed = 100,
  [string]$DumpFile = "s256_d64_seed100_top_O_beats128.hex",
  [string]$SummaryFile = "s256_d64_seed100_top_compare.json",
  [switch]$RunSimulation,
  [switch]$SkipSimulation
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

function Convert-ToSimPath {
  param([string]$Path)
  return $Path.Replace("\", "/")
}

if ($RunSimulation -and $SkipSimulation) {
  throw "Use either -RunSimulation or -SkipSimulation, not both."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot
. (Join-Path $PSScriptRoot "modelsim_worklib.ps1")

New-Item -ItemType Directory -Force -Path $VectorDir | Out-Null
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

$metadataPath = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_metadata.json")
$qPath = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_Q_beats64.hex")
$kPath = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_K_beats64.hex")
$vPath = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_V_beats64.hex")
$oGoldenPath = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_O_golden_beats64.hex")
$qPath128 = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_Q_beats128.hex")
$kPath128 = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_K_beats128.hex")
$vPath128 = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_V_beats128.hex")
$oGoldenPath128 = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_O_golden_beats128.hex")
$dumpPath = Convert-ToSimPath (Join-Path $RunDir $DumpFile)
$summaryPath = Convert-ToSimPath (Join-Path $RunDir $SummaryFile)
$simLogPath = Convert-ToSimPath (Join-Path $RunDir "$($CaseName)_top_sim.log")

Invoke-Checked python "-B" "scripts/generate_test_vectors.py" `
  "--seed" "$Seed" `
  "--sequence-length" "256" `
  "--dimension" "64" `
  "--case-name" $CaseName `
  "--output-dir" $VectorDir `
  "--stride-bytes" "128"

Invoke-Checked python "-B" "scripts/pack_vectors_128.py" `
  "--metadata" $metadataPath `
  "--output-dir" $VectorDir

if (-not $RunSimulation) {
  Write-Host ""
  Write-Host "S256 prepare-only mode: vectors and run directory are ready."
  Write-Host "Generated vectors: $VectorDir"
  Write-Host "Run outputs directory: $RunDir"
  Write-Host "DUT O beats128 dump target: $dumpPath"
  Write-Host "Scoreboard summary target: $summaryPath"
  Write-Host "Simulation log target: $simLogPath"
  Write-Host ""
  Write-Host "Run the full S256 top-compute scoreboard explicitly with:"
  Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_top_compute_s256_scoreboard.ps1 -RunSimulation"
  exit 0
}

Remove-PathWithAclRetry -Path $dumpPath
Remove-PathWithAclRetry -Path $summaryPath
Remove-PathWithAclRetry -Path $simLogPath

$modelSim = New-ModelSimWorkLib -LogicalName $WorkLib
Invoke-Checked vlog "-modelsimini" $modelSim.ModelsimIni "-timescale" "1ns/1ps" "-sv" "-work" $modelSim.LogicalName "-f" "rtl/filelist.f" "sim/axi_mem_model.sv" "sim/tb_top_compute_s32_smoke.sv" "sim/tb_top_compute_s256_smoke.sv"

$vsimArgs = @(
  "-c",
  "-lib", $modelSim.LogicalName,
  "tb_top_compute_s256_smoke",
  "+Q_BEATS128=$qPath128",
  "+K_BEATS128=$kPath128",
  "+V_BEATS128=$vPath128",
  "+O_GOLDEN_BEATS128=$oGoldenPath128",
  "+DUMP_O_BEATS128=$dumpPath",
  "-l", $simLogPath,
  "-do", "run -all; quit -f"
)
Invoke-ModelSimVsim -ModelsimIni $modelSim.ModelsimIni -Arguments $vsimArgs

if (-not (Test-Path $dumpPath)) {
  throw "Simulation did not produce DUT dump: $dumpPath"
}

Invoke-Checked python "-B" "scripts/compare_vector_output.py" `
  "--metadata" $metadataPath `
  "--dut-hex" $dumpPath `
  "--format" "beats128" `
  "--require-mae" "0" `
  "--require-maxae" "0" `
  "--dump-summary-json" $summaryPath

Write-Host "Generated vectors: $VectorDir"
Write-Host "DUT O beats128 dump: $dumpPath"
Write-Host "Scoreboard summary: $summaryPath"
Write-Host "Simulation log: $simLogPath"
