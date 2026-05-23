[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "word-match-windows-common.ps1")

$scriptDir = Get-WordMatchScriptDir -CommandPath $MyInvocation.MyCommand.Path
$runtimeDir = Get-WordMatchRuntimeDir -ScriptDir $scriptDir

New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

$nodeInfo = Resolve-WordMatchNodeCommand -ScriptDir $scriptDir -RequireCompatible

if ($nodeInfo) {
  Write-Host "已找到可用的 Node.js。"
  Write-Host "路径: $($nodeInfo.Path)"
  Write-Host "版本: $($nodeInfo.Version)"
} else {
  Write-Host "未找到 Node.js 18+，准备安装项目自带运行时。"
  Write-Host "将从 https://nodejs.org 下载官方 Windows 便携版。"
  $nodeInfo = Install-WordMatchPortableNode -ScriptDir $scriptDir
  Write-Host "Node.js 已安装到: $($nodeInfo.Path)"
  Write-Host "版本: $($nodeInfo.Version)"
}

$tailscaleInfo = Get-WordMatchTailscaleInfo
if ($tailscaleInfo -and $tailscaleInfo.IPv4.Count -gt 0) {
  Write-Host "已检测到 Tailscale: $($tailscaleInfo.Path)"
  Write-Host "当前 IPv4: $($tailscaleInfo.IPv4[0])"
} else {
  Write-Host "未检测到 Tailscale。"
  Write-Host "如果你只在本机使用，可以忽略。"
  Write-Host "如果要让别的设备访问这台 Windows 机器，再安装 Tailscale 即可。"
}

Write-Host ""
Write-Host "安装完成。"
Write-Host "本项目不依赖 npm、pnpm 或额外 node_modules。"
Write-Host "启动: 双击 start-word-match.cmd"
Write-Host "停止: 双击 stop-word-match.cmd"
Write-Host ""
Write-Host "如果你的网络环境较严格，请确认可以访问："
Write-Host "  - https://nodejs.org"
Write-Host "  - https://oss-cdn.tsdanci.com"
