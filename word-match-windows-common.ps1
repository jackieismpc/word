Set-StrictMode -Version Latest

$script:WordMatchMinimumNodeMajor = 18
$script:WordMatchPreferredNodeMajor = 20
$script:WordMatchFallbackNodeVersion = "v20.12.2"

function Get-WordMatchScriptDir {
  param([string]$CommandPath)

  if ([string]::IsNullOrWhiteSpace($CommandPath)) {
    return (Resolve-Path $PSScriptRoot).Path
  }

  (Resolve-Path (Split-Path -Parent $CommandPath)).Path
}

function Get-WordMatchRuntimeDir {
  param([string]$ScriptDir)

  Join-Path $ScriptDir ".runtime"
}

function Get-WordMatchPortableNodeDir {
  param([string]$ScriptDir)

  Join-Path (Get-WordMatchRuntimeDir -ScriptDir $ScriptDir) "node"
}

function Get-WordMatchServerScriptPath {
  param([string]$ScriptDir)

  Join-Path $ScriptDir "server.mjs"
}

function Get-WordMatchPidFilePath {
  param([string]$ScriptDir)

  Join-Path (Get-WordMatchRuntimeDir -ScriptDir $ScriptDir) "server.pid"
}

function Get-WordMatchLastPortFilePath {
  param([string]$ScriptDir)

  Join-Path (Get-WordMatchRuntimeDir -ScriptDir $ScriptDir) "last-port"
}

function Add-WordMatchUniquePath {
  param(
    [System.Collections.Generic.List[string]]$Paths,
    [string]$Candidate
  )

  if ([string]::IsNullOrWhiteSpace($Candidate)) {
    return
  }

  if (-not $Paths.Contains($Candidate)) {
    $Paths.Add($Candidate)
  }
}

function Add-WordMatchNodeCandidate {
  param(
    [System.Collections.Generic.List[string]]$Paths,
    [string]$Candidate
  )

  if ([string]::IsNullOrWhiteSpace($Candidate)) {
    return
  }

  $expanded = [Environment]::ExpandEnvironmentVariables($Candidate.Trim())
  Add-WordMatchUniquePath -Paths $Paths -Candidate $expanded
}

function Get-WordMatchNodeCandidates {
  param([string]$ScriptDir)

  $candidates = [System.Collections.Generic.List[string]]::new()
  $installRoots = [System.Collections.Generic.List[string]]::new()
  $homeDir = $env:USERPROFILE

  Add-WordMatchNodeCandidate -Paths $candidates -Candidate (Join-Path (Get-WordMatchPortableNodeDir -ScriptDir $ScriptDir) "node.exe")

  foreach ($commandName in @("node.exe", "node")) {
    try {
      $command = Get-Command $commandName -ErrorAction Stop | Select-Object -First 1
      Add-WordMatchNodeCandidate -Paths $candidates -Candidate $command.Source
      Add-WordMatchNodeCandidate -Paths $candidates -Candidate $command.Path
    } catch {
    }
  }

  foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LocalAppData)) {
    if (-not [string]::IsNullOrWhiteSpace($root)) {
      Add-WordMatchUniquePath -Paths $installRoots -Candidate $root
    }
  }

  foreach ($root in $installRoots) {
    if ($root -eq $env:LocalAppData) {
      Add-WordMatchNodeCandidate -Paths $candidates -Candidate (Join-Path $root "Programs\nodejs\node.exe")
      Add-WordMatchNodeCandidate -Paths $candidates -Candidate (Join-Path $root "Volta\bin\node.exe")
      Add-WordMatchNodeCandidate -Paths $candidates -Candidate (Join-Path $root "fnm\aliases\default\node.exe")
      continue
    }

    Add-WordMatchNodeCandidate -Paths $candidates -Candidate (Join-Path $root "nodejs\node.exe")
  }

  if ($env:APPDATA) {
    $nvmDir = Join-Path $env:APPDATA "nvm"
    if (Test-Path $nvmDir) {
      Get-ChildItem -Path $nvmDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object {
          Add-WordMatchNodeCandidate -Paths $candidates -Candidate (Join-Path $_.FullName "node.exe")
        }
    }
  }

  foreach ($candidate in @(
    $env:NVM_SYMLINK,
    (Join-Path $env:NVM_SYMLINK "node.exe"),
    $env:NVM_HOME,
    (Join-Path $env:NVM_HOME "node.exe"),
    $env:VOLTA_HOME,
    (Join-Path $env:VOLTA_HOME "bin\node.exe"),
    $env:FNM_DIR,
    (Join-Path $env:FNM_DIR "aliases\default\node.exe")
  )) {
    Add-WordMatchNodeCandidate -Paths $candidates -Candidate $candidate
  }

  if (-not [string]::IsNullOrWhiteSpace($homeDir)) {
    foreach ($candidate in @(
      (Join-Path $homeDir "scoop\apps\nodejs-current\current\node.exe"),
      (Join-Path $homeDir "scoop\apps\nodejs-lts\current\node.exe"),
      (Join-Path $homeDir ".volta\bin\node.exe")
    )) {
      Add-WordMatchNodeCandidate -Paths $candidates -Candidate $candidate
    }
  }

  $candidates.ToArray()
}

function Get-WordMatchNodeInfo {
  param([string]$NodeExe)

  if ([string]::IsNullOrWhiteSpace($NodeExe) -or -not (Test-Path $NodeExe)) {
    return $null
  }

  try {
    $version = (& $NodeExe -p "process.versions.node" 2>$null | Select-Object -First 1).Trim()
  } catch {
    return $null
  }

  if ([string]::IsNullOrWhiteSpace($version)) {
    return $null
  }

  $major = 0
  [void][int]::TryParse(($version.Split(".")[0]), [ref]$major)

  [pscustomobject]@{
    Path = (Resolve-Path $NodeExe).Path
    Version = $version
    Major = $major
    IsCompatible = $major -ge $script:WordMatchMinimumNodeMajor
  }
}

function Resolve-WordMatchNodeCommand {
  param(
    [string]$ScriptDir,
    [switch]$RequireCompatible
  )

  foreach ($candidate in Get-WordMatchNodeCandidates -ScriptDir $ScriptDir) {
    $nodeInfo = Get-WordMatchNodeInfo -NodeExe $candidate
    if (-not $nodeInfo) {
      continue
    }

    if ($RequireCompatible -and -not $nodeInfo.IsCompatible) {
      continue
    }

    return $nodeInfo
  }

  return $null
}

function Get-WordMatchFileText {
  param([string]$FilePath)

  if (-not (Test-Path $FilePath)) {
    return ""
  }

  try {
    (Get-Content -Path $FilePath -Raw -ErrorAction Stop).Trim()
  } catch {
    ""
  }
}

function Get-WordMatchProcessRecord {
  param([int]$ProcessId)

  try {
    Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
  } catch {
    $null
  }
}

function Test-WordMatchProcess {
  param(
    [string]$ScriptDir,
    [int]$ProcessId
  )

  $process = Get-WordMatchProcessRecord -ProcessId $ProcessId
  if (-not $process) {
    return $false
  }

  $commandLine = [string]$process.CommandLine
  if ([string]::IsNullOrWhiteSpace($commandLine)) {
    return $false
  }

  $serverPattern = [Regex]::Escape((Get-WordMatchServerScriptPath -ScriptDir $ScriptDir))
  return $commandLine -match "server\.mjs" -and $commandLine -match $serverPattern
}

function Find-WordMatchProcesses {
  param([string]$ScriptDir)

  $serverPattern = [Regex]::Escape((Get-WordMatchServerScriptPath -ScriptDir $ScriptDir))

  @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $commandLine = [string]$_.CommandLine
      -not [string]::IsNullOrWhiteSpace($commandLine) -and
      $commandLine -match "server\.mjs" -and
      $commandLine -match $serverPattern
    } |
    Sort-Object ProcessId)
}

function Test-WordMatchPortInUse {
  param([int]$Port)

  $listener = $null
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
    $listener.Start()
    return $false
  } catch {
    return $true
  } finally {
    if ($listener) {
      try {
        $listener.Stop()
      } catch {
      }
    }
  }
}

function Find-WordMatchAvailablePort {
  param(
    [int]$RequestedPort,
    [int]$MaxTries = 50
  )

  $port = $RequestedPort
  for ($i = 0; $i -lt $MaxTries; $i++) {
    if (-not (Test-WordMatchPortInUse -Port $port)) {
      return $port
    }

    $port += 1
  }

  return $null
}

function Get-WordMatchTailscaleInfo {
  $command = $null
  foreach ($commandName in @("tailscale.exe", "tailscale")) {
    try {
      $command = Get-Command $commandName -ErrorAction Stop | Select-Object -First 1
      break
    } catch {
    }
  }

  if (-not $command) {
    return $null
  }

  $ipv4 = @(& $command.Source ip -4 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  [pscustomobject]@{
    Path = $command.Source
    IPv4 = $ipv4
  }
}

function Wait-WordMatchHttpReady {
  param(
    [string]$Url,
    [int]$TimeoutSeconds = 15
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
      if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
        return $true
      }
    } catch {
    }

    Start-Sleep -Milliseconds 250
  }

  return $false
}

function Set-WordMatchTlsDefaults {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch {
  }
}

function Get-WordMatchPortableNodeArchiveName {
  $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()

  switch ($architecture) {
    "x64" { return "win-x64-zip" }
    "arm64" { return "win-arm64-zip" }
    "x86" { return "win-x86-zip" }
    default { throw "暂不支持的 Windows 架构: $architecture" }
  }
}

function Get-WordMatchPortableNodeRelease {
  param([string]$ArchiveName)

  Set-WordMatchTlsDefaults

  try {
    $index = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -Headers @{ "User-Agent" = "word-match-installer/1.0" }
    $candidates = @($index | Where-Object { $_.lts -and $_.files -contains $ArchiveName })

    $preferred = @($candidates | Where-Object {
      $major = 0
      [void][int]::TryParse((([string]$_.version).TrimStart("v").Split(".")[0]), [ref]$major)
      $major -eq $script:WordMatchPreferredNodeMajor
    })

    $release = $null
    if ($preferred.Count -gt 0) {
      $release = $preferred[0]
    } elseif ($candidates.Count -gt 0) {
      $release = $candidates[0]
    }

    if ($release) {
      return [pscustomobject]@{
        Version = [string]$release.version
        Url = "https://nodejs.org/dist/$($release.version)/node-$($release.version)-$ArchiveName.zip"
      }
    }
  } catch {
  }

  [pscustomobject]@{
    Version = $script:WordMatchFallbackNodeVersion
    Url = "https://nodejs.org/dist/$($script:WordMatchFallbackNodeVersion)/node-$($script:WordMatchFallbackNodeVersion)-$ArchiveName.zip"
  }
}

function Install-WordMatchPortableNode {
  param([string]$ScriptDir)

  $runtimeDir = Get-WordMatchRuntimeDir -ScriptDir $ScriptDir
  $nodeDir = Get-WordMatchPortableNodeDir -ScriptDir $ScriptDir
  $downloadDir = Join-Path $runtimeDir "download-node"
  $archiveName = Get-WordMatchPortableNodeArchiveName
  $release = Get-WordMatchPortableNodeRelease -ArchiveName $archiveName
  $zipPath = Join-Path $downloadDir "node.zip"
  $extractDir = Join-Path $downloadDir "extract"

  New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

  if (Test-Path $downloadDir) {
    Remove-Item -Path $downloadDir -Recurse -Force
  }

  New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
  Write-Host "正在下载 Node.js $($release.Version) ..."
  Invoke-WebRequest -Uri $release.Url -OutFile $zipPath -UseBasicParsing

  Write-Host "正在解压 Node.js ..."
  Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

  $expandedDir = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
  if (-not $expandedDir) {
    throw "Node.js 解压失败，未找到内容目录。"
  }

  if (Test-Path $nodeDir) {
    Remove-Item -Path $nodeDir -Recurse -Force
  }

  New-Item -ItemType Directory -Path $nodeDir -Force | Out-Null
  Copy-Item -Path (Join-Path $expandedDir.FullName "*") -Destination $nodeDir -Recurse -Force

  if (Test-Path $downloadDir) {
    Remove-Item -Path $downloadDir -Recurse -Force
  }

  $nodeInfo = Get-WordMatchNodeInfo -NodeExe (Join-Path $nodeDir "node.exe")
  if (-not $nodeInfo -or -not $nodeInfo.IsCompatible) {
    throw "Node.js 安装完成，但版本校验失败。"
  }

  $nodeInfo
}
