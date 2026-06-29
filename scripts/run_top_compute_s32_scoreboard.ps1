param(
  [string]$WorkLib = "work_top_compute_s32_scoreboard",
  [string]$VectorDir = "artifacts/vectors/s32_d64_seed103",
  [string]$BuildDir = "build/top_compute_s32",
  [string]$CaseName = "s32_d64_seed103",
  [int]$Seed = 103,
  [string]$DumpFile = "o_beats64.hex",
  [string]$SummaryFile = "summary.json"
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

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

New-Item -ItemType Directory -Force -Path $VectorDir | Out-Null
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$metadataPath = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_metadata.json")
$qPath = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_Q_beats64.hex")
$kPath = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_K_beats64.hex")
$vPath = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_V_beats64.hex")
$oGoldenPath = Convert-ToSimPath (Join-Path $VectorDir "$($CaseName)_O_golden_beats64.hex")
$dumpPath = Convert-ToSimPath (Join-Path $BuildDir $DumpFile)
$summaryPath = Convert-ToSimPath (Join-Path $BuildDir $SummaryFile)

if (Test-Path $dumpPath) {
  Remove-Item $dumpPath
}
if (Test-Path $summaryPath) {
  Remove-Item $summaryPath
}

Invoke-Checked python "-B" "scripts/generate_test_vectors.py" `
  "--seed" "$Seed" `
  "--sequence-length" "32" `
  "--dimension" "64" `
  "--case-name" $CaseName `
  "--output-dir" $VectorDir `
  "--stride-bytes" "128"

Invoke-Checked vlib $WorkLib
Invoke-Checked vlog "-sv" "-work" $WorkLib "-f" "rtl/filelist.f" "sim/axi_mem_model.sv" "sim/tb_top_compute_s32_smoke.sv"
Invoke-Checked vsim "-c" "-lib" $WorkLib `
  "tb_top_compute_s32_smoke" `
  "+Q_BEATS64=$qPath" `
  "+K_BEATS64=$kPath" `
  "+V_BEATS64=$vPath" `
  "+O_GOLDEN_BEATS64=$oGoldenPath" `
  "+DUMP_O_BEATS64=$dumpPath" `
  "-do" "run -all; quit -f"
Invoke-Checked python "-B" "scripts/compare_vector_output.py" `
  "--metadata" $metadataPath `
  "--dut-hex" $dumpPath `
  "--format" "beats64" `
  "--require-mae" "0" `
  "--require-maxae" "0" `
  "--dump-summary-json" $summaryPath

Write-Host "Generated vectors: $VectorDir"
Write-Host "DUT O beats64 dump: $dumpPath"
Write-Host "Scoreboard summary: $summaryPath"
