param(
  [string]$Version = "latest",
  [string]$InstallDir = $env:CONTROLKEEL_INSTALL_DIR,
  [string]$Repository = $(if ($env:CONTROLKEEL_GITHUB_REPO) { $env:CONTROLKEEL_GITHUB_REPO } else { "aryaminus/controlkeel" })
)

$ErrorActionPreference = "Stop"

function Get-DefaultInstallDir {
  if ($InstallDir) {
    return $InstallDir
  }

  return (Join-Path $env:LOCALAPPDATA "Programs\ControlKeel")
}

function Get-ReleaseBaseUrl {
  if ($Version -eq "latest") {
    return "https://github.com/$Repository/releases/latest/download"
  }

  return "https://github.com/$Repository/releases/download/v$Version"
}

$DestinationRoot = Get-DefaultInstallDir
$Destination = Join-Path $DestinationRoot "controlkeel.exe"
$DownloadUrl = "$(Get-ReleaseBaseUrl)/controlkeel-windows-x86_64.exe"

New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
Invoke-WebRequest -Uri $DownloadUrl -OutFile $Destination

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $UserPath) {
  $UserPath = ""
}

if (-not (($UserPath -split ";") -contains $DestinationRoot)) {
  $UpdatedPath = if ([string]::IsNullOrWhiteSpace($UserPath)) {
    $DestinationRoot
  }
  else {
    "$UserPath;$DestinationRoot"
  }

  [Environment]::SetEnvironmentVariable("Path", $UpdatedPath, "User")
  Write-Host "Added $DestinationRoot to the user PATH. Open a new shell to pick it up."
}

Write-Host "Installed ControlKeel to $Destination"
Write-Host "Run: controlkeel version"
