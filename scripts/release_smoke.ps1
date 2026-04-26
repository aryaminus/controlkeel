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
    [int]$TimeoutSeconds = 120
  )

  $stdoutPath = Join-Path $env:TEMP ("controlkeel-smoke-stdout-" + [guid]::NewGuid() + ".log")
  $stderrPath = Join-Path $env:TEMP ("controlkeel-smoke-stderr-" + [guid]::NewGuid() + ".log")

  try {
    $process = Start-Process -FilePath $BinaryPath `
      -ArgumentList $Arguments `
      -WorkingDirectory $WorkingDirectory `
      -NoNewWindow `
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

Invoke-BinaryStep -Arguments @("--help") -TimeoutSeconds 180 | Out-Null

Invoke-BinaryStep -Arguments @("version") | Out-Null

$tmpDir = Join-Path $env:TEMP ("controlkeel-release-smoke-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$homeDir = Join-Path $tmpDir "home"
New-Item -ItemType Directory -Path $homeDir | Out-Null
$serverStdoutLog = Join-Path $tmpDir "server-stdout.log"
$serverStderrLog = Join-Path $tmpDir "server-stderr.log"
$port = 4081
$started = $false
$succeeded = $false
$serverProcess = $null
$failureMessage = $null

function Test-TcpPortOpen {
  param(
    [string]$HostName,
    [int]$Port,
    [int]$TimeoutMs = 1000
  )

  $client = $null
  try {
    $client = [System.Net.Sockets.TcpClient]::new()
    $connectTask = $client.ConnectAsync($HostName, $Port)

    if ($null -eq $connectTask) {
      return $false
    }

    if (-not $connectTask.Wait($TimeoutMs)) {
      return $false
    }

    return $client.Connected
  }
  catch {
    return $false
  }
  finally {
    if ($null -ne $client) {
      $client.Dispose()
    }
  }
}

function Test-ProcessListeningPort {
  param(
    [int]$ProcessId,
    [int]$Port
  )

  try {
    $connections = Get-NetTCPConnection -OwningProcess $ProcessId -LocalPort $Port -State Listen -ErrorAction Stop
    if ($connections) {
      return $true
    }
  }
  catch {
    # Fall through to socket probes when Get-NetTCPConnection is unavailable or restricted.
  }

  if (Test-TcpPortOpen -HostName "127.0.0.1" -Port $Port -TimeoutMs 1000) {
    return $true
  }

  if (Test-TcpPortOpen -HostName "::1" -Port $Port -TimeoutMs 1000) {
    return $true
  }

  return $false
}

try {
  $env:HOME = $homeDir
  $env:CONTROLKEEL_HOME = $homeDir
  $env:APPDATA = $homeDir
  $env:DATABASE_PATH = Join-Path $tmpDir "controlkeel.db"
  $env:SECRET_KEY_BASE = "controlkeel-release-smoke-secret-0123456789abcdef0123456789abcdef0123456789abcdef"
  $env:PORT = "$port"
  $env:PHX_SERVER = "true"

  $serverProcess = Start-Process -FilePath $BinaryPath `
    -ArgumentList @("serve") `
    -NoNewWindow `
    -RedirectStandardOutput $serverStdoutLog `
    -RedirectStandardError $serverStderrLog `
    -WorkingDirectory $tmpDir `
    -PassThru
  $started = $true

  Start-Sleep -Seconds 1
  if ($serverProcess.HasExited) {
    throw "serve start failed"
  }

  for ($i = 0; $i -lt 20; $i++) {
    if (Test-ProcessListeningPort -ProcessId $serverProcess.Id -Port $port) {
      try { Stop-Process -Id $serverProcess.Id -Force } catch {}
      $started = $false
      $succeeded = $true
      exit 0
    }

    Start-Sleep -Seconds 1
  }

  throw "server smoke check failed"
}
catch {
  $failureMessage = $_.Exception.Message
  throw
}
finally {
  if ($started -and $serverProcess -and -not $serverProcess.HasExited) {
    try { Stop-Process -Id $serverProcess.Id -Force } catch {}
  }

  if (-not $succeeded) {
    $stdout = if (Test-Path $serverStdoutLog) { Get-Content $serverStdoutLog -Raw } else { "" }
    $stderr = if (Test-Path $serverStderrLog) { Get-Content $serverStderrLog -Raw } else { "" }
    $stdoutText = if ([string]::IsNullOrEmpty($stdout)) { "" } else { $stdout.Trim() }
    $stderrText = if ([string]::IsNullOrEmpty($stderr)) { "" } else { $stderr.Trim() }

    if ($failureMessage) {
      Write-Host "Smoke failure: $failureMessage"
    }

    if ($stdoutText -ne "" -or $stderrText -ne "") {
      Write-Host "--- server stdout ---`n$stdout`n--- server stderr ---`n$stderr"
    }
    else {
      Write-Host "No server output captured from smoke run."
    }
  }

  Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
