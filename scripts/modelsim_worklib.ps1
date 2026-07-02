function Invoke-ModelSimTool {
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

function Remove-PathWithAclRetry {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [switch]$Recurse
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  $resolvedPath = (Resolve-Path -LiteralPath $Path).Path

  try {
    Remove-Item -LiteralPath $resolvedPath -Force -Recurse:$Recurse -ErrorAction Stop
    return
  } catch [System.UnauthorizedAccessException] {
    $account = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $icaclsArgs = @($resolvedPath, "/grant", "${account}:F", "/C")
    if ((Get-Item -LiteralPath $resolvedPath -Force).PSIsContainer) {
      $icaclsArgs += "/T"
    }
    $oldErrorActionPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = "Continue"
      & icacls @icaclsArgs 2>$null | Out-Null
    } finally {
      $ErrorActionPreference = $oldErrorActionPreference
    }
    $item = Get-Item -LiteralPath $resolvedPath -Force
    try {
      Remove-Item -LiteralPath $resolvedPath -Force -Recurse:$Recurse -ErrorAction Stop
      return
    } catch [System.UnauthorizedAccessException] {
      if ($item.PSIsContainer) {
        throw
      }
      Set-Content -LiteralPath $resolvedPath -Value "" -NoNewline -ErrorAction Stop
      Write-Warning "Could not delete $resolvedPath; cleared it so this run cannot reuse stale contents."
    }
  }
}

function New-ModelSimWorkLib {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LogicalName
  )

  $safeName = ($LogicalName -replace '[^A-Za-z0-9_.-]', '_')
  $runRoot = Join-Path ([System.IO.Path]::GetTempPath()) "fa_accel_msim_$safeName"
  if (Test-Path -LiteralPath $runRoot) {
    Remove-PathWithAclRetry -Path $runRoot -Recurse
  }
  New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

  Push-Location $runRoot
  $oldModelsim = $env:MODELSIM
  try {
    $env:MODELSIM = $null
    Invoke-ModelSimTool vmap "-c"
  } finally {
    $env:MODELSIM = $oldModelsim
    Pop-Location
  }

  $modelsimIni = Join-Path $runRoot "modelsim.ini"
  $physicalLib = Join-Path $runRoot "work_phys"
  Invoke-ModelSimTool vlib $physicalLib
  Invoke-ModelSimTool vmap "-modelsimini" $modelsimIni $LogicalName $physicalLib

  [pscustomobject]@{
    LogicalName = $LogicalName
    ModelsimIni = $modelsimIni
    PhysicalLib = $physicalLib
    RunRoot = $runRoot
  }
}

function Invoke-ModelSimVsim {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ModelsimIni,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $oldModelsim = $env:MODELSIM
  try {
    $env:MODELSIM = $ModelsimIni
    Invoke-ModelSimTool vsim @Arguments
  } finally {
    $env:MODELSIM = $oldModelsim
  }
}
