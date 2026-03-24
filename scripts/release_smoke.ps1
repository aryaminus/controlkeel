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

function Test-McpInitialize {
  param(
    [string]$ProjectRoot,
    [int]$TimeoutSeconds = 20
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $BinaryPath
  $psi.WorkingDirectory = $ProjectRoot
  $psi.ArgumentList.Add("mcp")
  $psi.ArgumentList.Add("--project-root")
  $psi.ArgumentList.Add($ProjectRoot)
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $psi

  try {
    $null = $process.Start()

    $request = @{ jsonrpc = "2.0"; id = 1; method = "initialize"; params = @{} } | ConvertTo-Json -Compress
    $frame = "Content-Length: $($request.Length)`r`n`r`n$request"

    $process.StandardInput.Write($frame)
    $process.StandardInput.Close()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      try { $process.Kill($true) } catch {}
      throw "Timed out waiting for MCP initialize response"
    }

    if ($process.ExitCode -ne 0) {
      $stderr = $process.StandardError.ReadToEnd()
      throw "MCP initialize failed with exit code $($process.ExitCode): $stderr"
    }

    $stdout = $process.StandardOutput.ReadToEnd()

    if ($stdout -notmatch "Content-Length:" -or $stdout -notmatch '"result"') {
      throw "MCP initialize response did not contain a JSON-RPC result"
    }
  }
  finally {
    if (-not $process.HasExited) {
      try { $process.Kill($true) } catch {}
    }

    $process.Dispose()
  }
}

Invoke-BinaryStep -Arguments @("help") | Out-Null
Invoke-BinaryStep -Arguments @("version") | Out-Null

$tmpDir = Join-Path $env:TEMP ("controlkeel-release-smoke-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$homeDir = Join-Path $tmpDir "home"
New-Item -ItemType Directory -Path $homeDir | Out-Null

try {
  $env:HOME = $homeDir
  $env:CONTROLKEEL_HOME = $homeDir
  $env:APPDATA = $homeDir
  $env:DATABASE_PATH = Join-Path $tmpDir "controlkeel.db"
  $env:SECRET_KEY_BASE = "controlkeel-release-smoke-secret-0123456789abcdef0123456789abcdef0123456789abcdef"

  Invoke-BinaryStep -Arguments @("bootstrap") -WorkingDirectory $tmpDir | Out-Null

  if (-not (Test-Path (Join-Path $tmpDir "controlkeel/project.json"))) {
    throw "project binding missing"
  }

  if (-not (Test-Path (Join-Path $tmpDir "controlkeel/bin/controlkeel-mcp.cmd"))) {
    throw "mcp wrapper missing"
  }

  Test-McpInitialize -ProjectRoot $tmpDir

  $benchmarkOutput = Invoke-BinaryStep -Arguments @(
    "benchmark",
    "run",
    "--suite",
    "vibe_failures_v1",
    "--subjects",
    "controlkeel_validate",
    "--baseline-subject",
    "controlkeel_validate",
    "--scenario-slugs",
    "client_side_auth_bypass"
  ) -WorkingDirectory $tmpDir

  if ($benchmarkOutput -notmatch "Benchmark run #") {
    throw "benchmark smoke output did not include a persisted run"
  }

  Invoke-BinaryStep -Arguments @("attach", "codex-cli", "--scope", "project") -WorkingDirectory $tmpDir | Out-Null

  if (-not (Test-Path (Join-Path $tmpDir ".agents/skills/controlkeel-governance/SKILL.md"))) {
    throw "codex skills were not installed"
  }

  if (-not (Test-Path (Join-Path $tmpDir ".codex/agents/controlkeel-operator.toml"))) {
    throw "codex companion agent missing"
  }

  if (-not (Test-Path (Join-Path $homeDir ".codex/config.json"))) {
    throw "codex MCP config missing"
  }

  Invoke-BinaryStep -Arguments @("attach", "cursor") -WorkingDirectory $tmpDir | Out-Null

  if (-not (Test-Path (Join-Path $homeDir "Cursor/User/globalStorage/cursor.mcp.json"))) {
    throw "cursor MCP config missing"
  }

  if (-not (Test-Path (Join-Path $tmpDir "controlkeel/dist/instructions-only/AGENTS.md"))) {
    throw "instructions-only bundle missing after MCP-only attach"
  }
}
finally {
  Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
