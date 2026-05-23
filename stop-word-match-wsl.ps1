[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "word-match-wsl-common.ps1")

$scriptDir = Get-WordMatchScriptDir -CommandPath $MyInvocation.MyCommand.Path
$distribution = Get-WordMatchUbuntuDistributionName
if (-not $distribution) {
  Write-Host "未检测到 Ubuntu WSL，无需停止。"
  exit 0
}

Invoke-WordMatchWslBash -Distribution $distribution -ScriptDir $scriptDir -Command @'
chmod +x ./stop-word-match.sh
./stop-word-match.sh
'@
