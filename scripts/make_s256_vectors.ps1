param(
    [string]$OutputDir = "artifacts/vectors/s256_d64_seed100",
    [int]$Seed = 100,
    [string]$CaseName = "s256_d64_seed100"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

python -B scripts/generate_test_vectors.py `
    --seed $Seed `
    --sequence-length 256 `
    --dimension 64 `
    --case-name $CaseName `
    --output-dir $OutputDir `
    --stride-bytes 128

Write-Host "Generated S256 vectors under $OutputDir"
Write-Host "Keep this directory as a regression artifact; do not commit it by default."
