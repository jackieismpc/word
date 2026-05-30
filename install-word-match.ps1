[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "word-match-windows-common.ps1")

$scriptDir = Get-WordMatchScriptDir -CommandPath $MyInvocation.MyCommand.Path
$runtimeDir = Get-WordMatchRuntimeDir -ScriptDir $scriptDir

New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

$portableNode = Get-WordMatchPortableNodeInfo -ScriptDir $scriptDir
$offlineArchive = Find-WordMatchOfflineNodeArchive -ScriptDir $scriptDir
$systemNode = Resolve-WordMatchNodeCommand -ScriptDir $scriptDir -RequireCompatible -SkipPortable
$nodeInfo = $null

if ($portableNode) {
  $nodeInfo = $portableNode
  Write-Host "已安装并使用项目自带的离线 Node.js。"
  Write-Host "路径: $($nodeInfo.Path)"
  Write-Host "版本: $($nodeInfo.Version)"
} elseif ($offlineArchive) {
  $offlineNodeDir = Get-WordMatchOfflineNodeDir -ScriptDir $scriptDir
  Write-Host "未找到 Node.js 18+，准备安装项目自带运行时。"
  Write-Host "安装顺序："
  Write-Host "  1. 优先使用项目目录中的离线包：$offlineNodeDir"
  Write-Host "  2. 如果显式允许联网下载，才会尝试从 https://nodejs.org 下载官方 Windows 便携版"
  $nodeInfo = Install-WordMatchPortableNode -ScriptDir $scriptDir
  Write-Host "Node.js 已安装到: $($nodeInfo.Path)"
  Write-Host "版本: $($nodeInfo.Version)"
} elseif ($systemNode) {
  $nodeInfo = $systemNode
  Write-Host "已找到系统中的可用 Node.js。"
  Write-Host "路径: $($nodeInfo.Path)"
  Write-Host "版本: $($nodeInfo.Version)"
  Write-Host "提示：如果希望优先使用项目自带离线 Node.js，请把 zip 包放到 $(Get-WordMatchOfflineNodeDir -ScriptDir $scriptDir)"
} else {
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
Write-Host "离线 Windows 安装建议："
Write-Host "  - 先在可联网机器上准备 offline-assets\\node 中的离线包"
Write-Host "  - 再把整个项目目录复制到 Windows"
Write-Host ""
Write-Host "如需显式允许在线下载 Node.js，请设置："
Write-Host "  - WORD_MATCH_ALLOW_ONLINE_DOWNLOAD=1"
