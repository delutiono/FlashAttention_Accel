param(
  [Parameter(Mandatory = $true)]
  [string[]]$WorkLib,
  [switch]$KillOwnerProcesses
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$account = "$env:USERDOMAIN\$env:USERNAME"

foreach ($lib in $WorkLib) {
  $libPath = Resolve-Path -LiteralPath $lib -ErrorAction SilentlyContinue
  if (-not $libPath) {
    continue
  }

  $fullLibPath = $libPath.Path
  if (-not $fullLibPath.StartsWith($repoRoot)) {
    throw "Refusing to clean ModelSim lock outside repository: $fullLibPath"
  }

  $lockPath = Join-Path $fullLibPath "_lock"
  if (-not (Test-Path -LiteralPath $lockPath)) {
    continue
  }

  $lockText = Get-Content -LiteralPath $lockPath -ErrorAction SilentlyContinue
  $ownerProcess = $null
  if ($lockText -match 'pid = (\d+)') {
    $ownerProcess = Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue
  }

  if ($ownerProcess) {
    if ($KillOwnerProcesses -and ($ownerProcess.ProcessName -match '^(vsim|vsimk|vlog|vlib|vopt|modelsim|questa)$')) {
      Stop-Process -Id $ownerProcess.Id -Force
      Start-Sleep -Milliseconds 250
    } else {
      Write-Host "ModelSim lock still has live owner pid=$($ownerProcess.Id); keeping $lockPath"
      continue
    }
  }

  Write-Host "Cleaning stale ModelSim lock: $lockPath"
  & icacls $lockPath /grant "${account}:F" | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "icacls failed while repairing $lockPath"
  }
  Remove-Item -LiteralPath $lockPath -Force
}
