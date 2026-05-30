[CmdletBinding()]
param(
  [bool]$OpenBrowser = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "word-match-windows-common.ps1")

$scriptDir = Get-WordMatchScriptDir -CommandPath $MyInvocation.MyCommand.Path
$runtimeDir = Get-WordMatchRuntimeDir -ScriptDir $scriptDir
$pidFile = Get-WordMatchPidFilePath -ScriptDir $scriptDir
$lastPortFile = Get-WordMatchLastPortFilePath -ScriptDir $scriptDir
$serverScript = Get-WordMatchServerScriptPath -ScriptDir $scriptDir
$stdoutLog = Join-Path $runtimeDir "server.stdout.log"
$stderrLog = Join-Path $runtimeDir "server.stderr.log"

New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

$nodeInfo = Get-WordMatchPortableNodeInfo -ScriptDir $scriptDir
$offlineArchive = Find-WordMatchOfflineNodeArchive -ScriptDir $scriptDir

if (-not $nodeInfo -and $offlineArchive) {
  Write-Host "检测到项目离线 Node.js 包，正在安装本地运行时..."
  & (Join-Path $scriptDir "install-word-match.ps1")
  $nodeInfo = Get-WordMatchPortableNodeInfo -ScriptDir $scriptDir
}

if (-not $nodeInfo) {
  $nodeInfo = Resolve-WordMatchNodeCommand -ScriptDir $scriptDir -RequireCompatible -SkipPortable
}

if (-not $nodeInfo) {
  Write-Host "未找到可用的 Node.js，正在自动安装本地运行时..."
  & (Join-Path $scriptDir "install-word-match.ps1")
  $nodeInfo = Get-WordMatchPortableNodeInfo -ScriptDir $scriptDir
  if (-not $nodeInfo) {
    $nodeInfo = Resolve-WordMatchNodeCommand -ScriptDir $scriptDir -RequireCompatible -SkipPortable
  }
}

if (-not $nodeInfo) {
  throw "无法找到可用的 Node.js，请先运行 install-word-match.cmd。"
}

$requestedPort = 12345
if ($env:PORT -match "^\d+$") {
  $requestedPort = [int]$env:PORT
}

$bindHost = if ($env:BIND_HOST) {
  $env:BIND_HOST
} elseif ($env:WORD_MATCH_HOST) {
  $env:WORD_MATCH_HOST
} elseif ($env:HOST) {
  $env:HOST
} else {
  "0.0.0.0"
}

$existingPidText = Get-WordMatchFileText -FilePath $pidFile
if ($existingPidText) {
  $existingPid = 0
  if ([int]::TryParse($existingPidText, [ref]$existingPid) -and (Test-WordMatchProcess -ScriptDir $scriptDir -ProcessId $existingPid)) {
    $existingPort = Get-WordMatchFileText -FilePath $lastPortFile
    if (-not $existingPort) {
      $existingPort = "$requestedPort"
    }

    $localUrl = "http://127.0.0.1:$existingPort"
    Write-Host "单词对对碰已经在运行。"
    Write-Host "PID: $existingPid"
    Write-Host "访问地址: $localUrl"

    $tailscaleInfo = Get-WordMatchTailscaleInfo
    if ($tailscaleInfo -and $tailscaleInfo.IPv4.Count -gt 0) {
      Write-Host "Tailscale 地址: http://$($tailscaleInfo.IPv4[0]):$existingPort"
    }

    if ($OpenBrowser) {
      Start-Process $localUrl | Out-Null
    }

    exit 0
  }

  Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
}

$existingProcesses = @(Find-WordMatchProcesses -ScriptDir $scriptDir)
if ($existingProcesses.Count -gt 0) {
  $existingPid = [int]$existingProcesses[0].ProcessId
  $existingPort = Get-WordMatchFileText -FilePath $lastPortFile
  if (-not $existingPort) {
    $existingPort = "$requestedPort"
  }

  Set-Content -Path $pidFile -Value "$existingPid`n" -Encoding utf8

  $localUrl = "http://127.0.0.1:$existingPort"
  Write-Host "单词对对碰已经在运行。"
  Write-Host "PID: $existingPid"
  Write-Host "访问地址: $localUrl"

  $tailscaleInfo = Get-WordMatchTailscaleInfo
  if ($tailscaleInfo -and $tailscaleInfo.IPv4.Count -gt 0) {
    Write-Host "Tailscale 地址: http://$($tailscaleInfo.IPv4[0]):$existingPort"
  }

  if ($OpenBrowser) {
    Start-Process $localUrl | Out-Null
  }

  exit 0
}

$port = Find-WordMatchAvailablePort -RequestedPort $requestedPort
if (-not $port) {
  throw "没有找到可用端口，已尝试范围 ${requestedPort}-$($requestedPort + 49)。"
}

if ($port -ne $requestedPort) {
  Write-Host "端口 $requestedPort 已被占用，已自动切换到 $port。"
}

Set-Content -Path $lastPortFile -Value "$port`n" -Encoding utf8

if (Test-Path $stdoutLog) {
  Remove-Item -Path $stdoutLog -Force
}

if (Test-Path $stderrLog) {
  Remove-Item -Path $stderrLog -Force
}

$previousPort = $env:PORT
$previousBindHost = $env:BIND_HOST
$previousPidFile = $env:WORD_MATCH_PID_FILE

try {
  $env:PORT = "$port"
  $env:BIND_HOST = $bindHost
  $env:WORD_MATCH_PID_FILE = $pidFile

  $process = Start-Process -FilePath $nodeInfo.Path `
    -ArgumentList @($serverScript) `
    -WorkingDirectory $scriptDir `
    -PassThru `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog
} finally {
  $env:PORT = $previousPort
  $env:BIND_HOST = $previousBindHost
  $env:WORD_MATCH_PID_FILE = $previousPidFile
}

$localUrl = "http://127.0.0.1:$port"
$ready = Wait-WordMatchHttpReady -Url "$localUrl/api/bootstrap" -TimeoutSeconds 15

if (-not $ready) {
  if ($process.HasExited) {
    Write-Host "服务启动失败。"
    if (Test-Path $stderrLog) {
      Write-Host "错误日志:"
      Get-Content -Path $stderrLog -Tail 20
    }
    exit 1
  }

  Write-Host "服务已启动，但健康检查超时。你仍然可以尝试手动打开：$localUrl"
} else {
  Write-Host "启动单词对对碰本地版..."
  Write-Host "工作目录: $scriptDir"
  Write-Host "Node: $($nodeInfo.Path)"
  Write-Host "访问地址: $localUrl"
}

$tailscaleInfo = Get-WordMatchTailscaleInfo
if ($tailscaleInfo -and $tailscaleInfo.IPv4.Count -gt 0) {
  Write-Host "Tailscale 地址: http://$($tailscaleInfo.IPv4[0]):$port"
} else {
  Write-Host "Tailscale 地址: 未检测到，可在安装并登录后自动显示"
}

Write-Host "日志输出: $stdoutLog"
if ($OpenBrowser) {
  Start-Process $localUrl | Out-Null
}
