Set-StrictMode -Version Latest

$script:WordMatchMinimumNodeMajor = 18
$script:WordMatchPreferredNodeMajor = 20
$script:WordMatchFallbackNodeVersion = "v20.12.2"
$script:WordMatchOfflineAssetsDirName = "offline-assets"

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

function Get-WordMatchOfflineAssetsDir {
  param([string]$ScriptDir)

  Join-Path $ScriptDir $script:WordMatchOfflineAssetsDirName
}

function Get-WordMatchOfflineNodeDir {
  param([string]$ScriptDir)

  Join-Path (Get-WordMatchOfflineAssetsDir -ScriptDir $ScriptDir) "node"
}

function Get-WordMatchPortableNodeDir {
  param([string]$ScriptDir)

  Join-Path (Get-WordMatchRuntimeDir -ScriptDir $ScriptDir) "node"
}

function Test-WordMatchAllowOnlineDownload {
  $value = [string]$env:WORD_MATCH_ALLOW_ONLINE_DOWNLOAD
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $false
  }

  @("1", "true", "yes", "on") -contains $value.Trim().ToLowerInvariant()
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

function Add-WordMatchNodeCandidateFromEnv {
  param(
    [System.Collections.Generic.List[string]]$Paths,
    [string]$BasePath,
    [string]$ChildPath = ""
  )

  if ([string]::IsNullOrWhiteSpace($BasePath)) {
    return
  }

  Add-WordMatchNodeCandidate -Paths $Paths -Candidate $BasePath

  if (-not [string]::IsNullOrWhiteSpace($ChildPath)) {
    Add-WordMatchNodeCandidate -Paths $Paths -Candidate (Join-Path $BasePath $ChildPath)
  }
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

  Add-WordMatchNodeCandidateFromEnv -Paths $candidates -BasePath $env:NVM_SYMLINK -ChildPath "node.exe"
  Add-WordMatchNodeCandidateFromEnv -Paths $candidates -BasePath $env:NVM_HOME -ChildPath "node.exe"
  Add-WordMatchNodeCandidateFromEnv -Paths $candidates -BasePath $env:VOLTA_HOME -ChildPath "bin\node.exe"
  Add-WordMatchNodeCandidateFromEnv -Paths $candidates -BasePath $env:FNM_DIR -ChildPath "aliases\default\node.exe"

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
    [switch]$RequireCompatible,
    [switch]$SkipPortable
  )

  $candidates = if ($SkipPortable) {
    @(Get-WordMatchNodeCandidates -ScriptDir $ScriptDir | Where-Object {
      $_ -ne (Join-Path (Get-WordMatchPortableNodeDir -ScriptDir $ScriptDir) "node.exe")
    })
  } else {
    Get-WordMatchNodeCandidates -ScriptDir $ScriptDir
  }

  foreach ($candidate in $candidates) {
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

function Get-WordMatchPortableNodeInfo {
  param([string]$ScriptDir)

  Get-WordMatchNodeInfo -NodeExe (Join-Path (Get-WordMatchPortableNodeDir -ScriptDir $ScriptDir) "node.exe")
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

function Get-WordMatchPortableNodeArchiveBaseName {
  $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()

  switch ($architecture) {
    "x64" { return "win-x64" }
    "arm64" { return "win-arm64" }
    "x86" { return "win-x86" }
    default { throw "暂不支持的 Windows 架构: $architecture" }
  }
}

function Get-WordMatchPortableNodeArchiveName {
  "$(Get-WordMatchPortableNodeArchiveBaseName)-zip"
}

function Get-WordMatchPortableNodeArchiveFileName {
  param(
    [string]$Version = $script:WordMatchFallbackNodeVersion
  )

  "node-$Version-$(Get-WordMatchPortableNodeArchiveBaseName).zip"
}

function Find-WordMatchOfflineNodeArchive {
  param([string]$ScriptDir)

  $offlineNodeDir = Get-WordMatchOfflineNodeDir -ScriptDir $ScriptDir
  if (-not (Test-Path $offlineNodeDir)) {
    return $null
  }

  $archiveBaseName = Get-WordMatchPortableNodeArchiveBaseName
  foreach ($candidateName in @(
    (Get-WordMatchPortableNodeArchiveFileName),
    "node-$archiveBaseName.zip",
    "node.zip"
  )) {
    $candidatePath = Join-Path $offlineNodeDir $candidateName
    if (Test-Path $candidatePath) {
      return (Resolve-Path $candidatePath).Path
    }
  }

  $matchedArchive = Get-ChildItem -Path $offlineNodeDir -Filter "node-*-$archiveBaseName.zip" -File -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1
  if ($matchedArchive) {
    return $matchedArchive.FullName
  }

  return $null
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
  $zipPath = Join-Path $downloadDir "node.zip"
  $extractDir = Join-Path $downloadDir "extract"
  $offlineArchive = Find-WordMatchOfflineNodeArchive -ScriptDir $ScriptDir

  New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

  if (Test-Path $downloadDir) {
    Remove-Item -Path $downloadDir -Recurse -Force
  }

  New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
  if ($offlineArchive) {
    Write-Host "检测到离线 Node.js 包，正在使用: $offlineArchive"
    Copy-Item -Path $offlineArchive -Destination $zipPath -Force
  } else {
    if (-not (Test-WordMatchAllowOnlineDownload)) {
      $offlineNodeDir = Get-WordMatchOfflineNodeDir -ScriptDir $ScriptDir
      $expectedName = Get-WordMatchPortableNodeArchiveFileName
      throw "未找到离线 Node.js 包，且当前不允许联网下载。请先把官方便携包放到 $offlineNodeDir，例如 $expectedName；如需显式允许联网下载，请设置环境变量 WORD_MATCH_ALLOW_ONLINE_DOWNLOAD=1。"
    }

    $archiveName = Get-WordMatchPortableNodeArchiveName
    $release = Get-WordMatchPortableNodeRelease -ArchiveName $archiveName
    Write-Host "未找到离线 Node.js 包，正在下载 Node.js $($release.Version) ..."
    try {
      Invoke-WebRequest -Uri $release.Url -OutFile $zipPath -UseBasicParsing
    } catch {
      $offlineNodeDir = Get-WordMatchOfflineNodeDir -ScriptDir $ScriptDir
      $expectedName = Get-WordMatchPortableNodeArchiveFileName
      throw "Node.js 在线下载失败。请先把官方便携包放到 $offlineNodeDir，例如 $expectedName，然后重新运行安装脚本。"
    }
  }

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
