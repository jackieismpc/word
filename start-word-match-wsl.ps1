[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "word-match-wsl-common.ps1")

$scriptDir = Get-WordMatchScriptDir -CommandPath $MyInvocation.MyCommand.Path
$distribution = Get-WordMatchUbuntuDistributionName
if (-not $distribution) {
  throw "未检测到 Ubuntu WSL，请先运行 install-word-match-wsl.cmd。"
}

Write-Host "正在通过 WSL2 Ubuntu 启动服务..."
Invoke-WordMatchWslBash -Distribution $distribution -ScriptDir $scriptDir -Command @'
chmod +x ./install-word-match.sh ./start-word-match.sh ./stop-word-match.sh
./install-word-match.sh
./start-word-match.sh
'@

$lastPortFile = Join-Path $scriptDir ".runtime\last-port"
$port = if (Test-Path $lastPortFile) {
  (Get-Content -Path $lastPortFile -Raw -ErrorAction SilentlyContinue).Trim()
} else {
  "12345"
}

if (-not ($port -match "^\d+$")) {
  $port = "12345"
}

$url = "http://127.0.0.1:$port"
Write-Host "访问地址: $url"
Start-Process $url | Out-Null
