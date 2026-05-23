[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "word-match-wsl-common.ps1")

$scriptDir = Get-WordMatchScriptDir -CommandPath $MyInvocation.MyCommand.Path

if (-not (Test-WordMatchIsAdministrator)) {
  Write-Host "首次安装 WSL2/Ubuntu 需要管理员权限，正在尝试提权..."
  $process = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $MyInvocation.MyCommand.Path) `
    -Verb RunAs `
    -PassThru `
    -Wait
  exit $process.ExitCode
}

$distribution = Ensure-WordMatchUbuntuWsl

Write-Host "使用的 Ubuntu 发行版: $distribution"
Write-Host "正在准备 Ubuntu 基础环境..."
Invoke-WordMatchWslBash -Distribution $distribution -ScriptDir $scriptDir -Command @'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl xz-utils
chmod +x ./install-word-match.sh ./start-word-match.sh ./stop-word-match.sh
./install-word-match.sh
'@

Write-Host ""
Write-Host "WSL2 Ubuntu 安装链路已准备完成。"
Write-Host "启动: 双击 start-word-match-wsl.cmd"
Write-Host "停止: 双击 stop-word-match-wsl.cmd"
