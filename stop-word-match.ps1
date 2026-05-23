[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "word-match-windows-common.ps1")

$scriptDir = Get-WordMatchScriptDir -CommandPath $MyInvocation.MyCommand.Path
$pidFile = Get-WordMatchPidFilePath -ScriptDir $scriptDir
$lastPortFile = Get-WordMatchLastPortFilePath -ScriptDir $scriptDir

$pids = [System.Collections.Generic.List[int]]::new()
$nodeInfo = Resolve-WordMatchNodeCommand -ScriptDir $scriptDir -RequireCompatible

$pidText = Get-WordMatchFileText -FilePath $pidFile
if ($pidText) {
  $pidFromFile = 0
  if ([int]::TryParse($pidText, [ref]$pidFromFile) -and (Test-WordMatchProcess -ScriptDir $scriptDir -ProcessId $pidFromFile)) {
    $pids.Add($pidFromFile)
  } else {
    Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
  }
}

foreach ($process in Find-WordMatchProcesses -ScriptDir $scriptDir) {
  $processId = [int]$process.ProcessId
  if (-not $pids.Contains($processId)) {
    $pids.Add($processId)
  }
}

if ($pids.Count -eq 0) {
  Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
  Write-Host "没有找到正在运行的单词对对碰服务。"
  exit 0
}

$port = Get-WordMatchFileText -FilePath $lastPortFile
if (-not $port) {
  $port = "未知端口"
}

Write-Host "正在停止单词对对碰服务..."
Write-Host "PID: $($pids -join ', ')"
Write-Host "端口: $port"

foreach ($processId in $pids) {
  $stopped = $false

  if ($nodeInfo) {
    try {
      & $nodeInfo.Path -e "try { process.kill($processId, 'SIGTERM'); } catch (error) { process.exit(1); }" | Out-Null
      $stopped = $true
    } catch {
    }
  }

  if (-not $stopped) {
    try {
      Stop-Process -Id $processId -ErrorAction Stop
    } catch {
    }
  }
}

$deadline = (Get-Date).AddSeconds(5)
while ((Get-Date) -lt $deadline) {
  $alive = $false
  foreach ($processId in $pids) {
    if (Test-WordMatchProcess -ScriptDir $scriptDir -ProcessId $processId) {
      $alive = $true
      break
    }
  }

  if (-not $alive) {
    Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $lastPortFile -Force -ErrorAction SilentlyContinue
    Write-Host "服务已停止。"
    exit 0
  }

  Start-Sleep -Milliseconds 250
}

Write-Host "服务未在预期时间内退出，尝试强制结束..."
foreach ($processId in $pids) {
  try {
    Stop-Process -Id $processId -Force -ErrorAction Stop
  } catch {
  }
}

Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
Remove-Item -Path $lastPortFile -Force -ErrorAction SilentlyContinue
Write-Host "服务已强制停止。"
