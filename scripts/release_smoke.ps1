param(
  [Parameter(Mandatory = $true)]
  [string]$BinaryPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $BinaryPath)) {
  throw "Binary not found: $BinaryPath"
}

function Invoke-BinaryStep {
  param(
    [string[]]$Arguments,
    [string]$WorkingDirectory = (Get-Location).Path,
    [int]$TimeoutSeconds = 60
  )

  $stdoutPath = Join-Path $env:TEMP ("controlkeel-smoke-stdout-" + [guid]::NewGuid() + ".log")
  $stderrPath = Join-Path $env:TEMP ("controlkeel-smoke-stderr-" + [guid]::NewGuid() + ".log")

  try {
    $process = Start-Process -FilePath $BinaryPath `
      -ArgumentList $Arguments `
      -WorkingDirectory $WorkingDirectory `
      -RedirectStandardOutput $stdoutPath `
      -RedirectStandardError $stderrPath `
      -PassThru

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      try { $process.Kill($true) } catch {}
      throw "Timed out running: $BinaryPath $($Arguments -join ' ')"
    }

    if ($process.ExitCode -ne 0) {
      $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { "" }
      throw "Command failed with exit code $($process.ExitCode): $BinaryPath $($Arguments -join ' ')`n$stderr"
    }

    if (Test-Path $stdoutPath) {
      return Get-Content $stdoutPath -Raw
    }

    return ""
  }
  finally {
    Remove-Item -Force $stdoutPath -ErrorAction SilentlyContinue
    Remove-Item -Force $stderrPath -ErrorAction SilentlyContinue
  }
}

Invoke-BinaryStep -Arguments @("version") | Out-Null

$tmpDir = Join-Path $env:TEMP ("controlkeel-release-smoke-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$homeDir = Join-Path $tmpDir "home"
New-Item -ItemType Directory -Path $homeDir | Out-Null
$serverLog = Join-Path $tmpDir "server.log"
$port = 4081
$started = $false

try {
  $env:HOME = $homeDir
  $env:CONTROLKEEL_HOME = $homeDir
  $env:APPDATA = $homeDir
  $env:DATABASE_PATH = Join-Path $tmpDir "controlkeel.db"
  $env:SECRET_KEY_BASE = "controlkeel-release-smoke-secret-0123456789abcdef0123456789abcdef0123456789abcdef"
  $env:PORT = "$port"
  $env:PHX_SERVER = "true"

  Start-Process -FilePath $BinaryPath `
    -ArgumentList @("daemon") `
    -RedirectStandardOutput $serverLog `
    -RedirectStandardError $serverLog `
    -WorkingDirectory $tmpDir `
    -Wait
  $started = $true

  for ($i = 0; $i -lt 20; $i++) {
    try {
      $null = Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -TimeoutSec 2 -UseBasicParsing
      Invoke-BinaryStep -Arguments @("stop") | Out-Null
      $started = $false
      exit 0
    }
    catch {
      Start-Sleep -Seconds 1
    }
  }

  throw "server smoke check failed"
}
finally {
  if ($started) {
    try { Invoke-BinaryStep -Arguments @("stop") | Out-Null } catch {}
  }

  if (Test-Path $serverLog) {
    Write-Error "--- server log ---`n$(Get-Content $serverLog -Raw)"
  }

  Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
