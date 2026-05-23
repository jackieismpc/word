Set-StrictMode -Version Latest

function Get-WordMatchScriptDir {
  param([string]$CommandPath)

  if ([string]::IsNullOrWhiteSpace($CommandPath)) {
    return (Resolve-Path $PSScriptRoot).Path
  }

  (Resolve-Path (Split-Path -Parent $CommandPath)).Path
}

function Test-WordMatchIsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-WordMatchWindowsPathToWsl {
  param([string]$WindowsPath)

  $fullPath = [IO.Path]::GetFullPath($WindowsPath)
  $normalized = $fullPath -replace "\\", "/"
  if ($normalized -match "^([A-Za-z]):/(.*)$") {
    return "/mnt/$($matches[1].ToLowerInvariant())/$($matches[2])"
  }

  throw "暂不支持的 Windows 路径: $WindowsPath"
}

function ConvertTo-WordMatchBashLiteral {
  param([string]$Text)

  "'" + ($Text -replace "'", "'\''") + "'"
}

function Get-WordMatchUbuntuDistributionName {
  $distributions = @(& wsl.exe -l -q 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  foreach ($candidate in @("Ubuntu", "Ubuntu-24.04", "Ubuntu-22.04", "Ubuntu-20.04")) {
    if ($distributions -contains $candidate) {
      return $candidate
    }
  }

  return $null
}

function Ensure-WordMatchUbuntuWsl {
  if (-not (Get-Command "wsl.exe" -ErrorAction SilentlyContinue)) {
    throw "当前 Windows 未提供 wsl.exe，无法启用 WSL2。"
  }

  if (-not (Test-WordMatchIsAdministrator)) {
    throw "首次安装 WSL2/Ubuntu 需要管理员权限，请以管理员身份运行 install-word-match-wsl.cmd。"
  }

  $distribution = Get-WordMatchUbuntuDistributionName
  if ($distribution) {
    return $distribution
  }

  Write-Host "正在安装 WSL2 和 Ubuntu..."
  & wsl.exe --install --distribution Ubuntu --no-launch
  $installExitCode = $LASTEXITCODE
  if ($installExitCode -ne 0) {
    throw "wsl --install 执行失败，退出码: $installExitCode"
  }

  try {
    & wsl.exe --set-default-version 2 | Out-Null
  } catch {
  }

  $distribution = Get-WordMatchUbuntuDistributionName
  if (-not $distribution) {
    throw "WSL2/Ubuntu 已开始安装，但当前还未完成注册。请先重启 Windows，然后再次运行 install-word-match-wsl.cmd。"
  }

  return $distribution
}

function Invoke-WordMatchWslBash {
  param(
    [string]$Distribution,
    [string]$ScriptDir,
    [string]$Command
  )

  $wslScriptDir = Convert-WordMatchWindowsPathToWsl -WindowsPath $ScriptDir
  $bashCommand = "cd $(ConvertTo-WordMatchBashLiteral -Text $wslScriptDir) && $Command"

  & wsl.exe -d $Distribution --user root -- bash -lc $bashCommand
  if ($LASTEXITCODE -ne 0) {
    throw "WSL 命令执行失败，退出码: $LASTEXITCODE"
  }
}
