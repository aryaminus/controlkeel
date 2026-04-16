#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONTROLKEEL_BIN="${CONTROLKEEL_BIN:-controlkeel}"
RUN_FULL=0

if [[ "${1:-}" == "--full" ]]; then
  RUN_FULL=1
fi

log() {
  printf '%s\n' "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "ERROR missing required command: $1"
    exit 1
  fi
}

require_cmd "$CONTROLKEEL_BIN"
require_cmd mix
require_cmd node
require_cmd python3

run_with_timeout() {
  local output_file="$1"
  shift

  python3 - "$output_file" "$@" <<'PY'
import subprocess
import sys

output_file = sys.argv[1]
command = sys.argv[2:]

try:
  completed = subprocess.run(command, capture_output=True, text=True, timeout=120)
  text = (completed.stdout or "") + (completed.stderr or "")
  with open(output_file, "w", encoding="utf-8") as f:
    f.write(text)
  sys.exit(completed.returncode)
except subprocess.TimeoutExpired as exc:
  stdout = exc.stdout or ""
  stderr = exc.stderr or ""
  if isinstance(stdout, bytes):
    stdout = stdout.decode("utf-8", errors="replace")
  if isinstance(stderr, bytes):
    stderr = stderr.decode("utf-8", errors="replace")
  with open(output_file, "w", encoding="utf-8") as f:
    f.write(stdout + stderr + "\nTIMEOUT after 120s\n")
  sys.exit(124)
PY
}

log "== ControlKeel version parity =="
log "system binary: $(command -v "$CONTROLKEEL_BIN")"
"$CONTROLKEEL_BIN" version
mix run -e 'IO.puts("source tree version: " <> Mix.Project.config()[:version])'

log ""
log "== Release parity (system CLI) =="
"$CONTROLKEEL_BIN" attach copilot >/tmp/ck_attach_copilot.out 2>&1 || {
  cat /tmp/ck_attach_copilot.out
  log "ERROR system CLI failed to attach copilot"
  exit 1
}

log ""
log "== Copilot surface checks =="

required_files=(
  ".github/mcp.json"
  ".vscode/mcp.json"
  ".github/copilot-instructions.md"
  ".github/agents/controlkeel-operator.agent.md"
  ".github/commands/controlkeel-review.md"
  ".github/skills/controlkeel-governance/SKILL.md"
  "controlkeel/dist/copilot-plugin/plugin.json"
  "controlkeel/dist/copilot-plugin/.mcp.json"
  "controlkeel/dist/copilot-plugin/skills/controlkeel-governance/SKILL.md"
)

for path in "${required_files[@]}"; do
  if [[ -f "$path" ]]; then
    log "OK file $path"
  else
    log "ERROR missing file $path"
    exit 1
  fi
done

log ""
log "== MCP probe (bin/controlkeel-mcp) =="
probe_mcp_launcher() {
  local launcher="$1"

  if [[ ! -x "$launcher" ]]; then
  log "WARN launcher not present: $launcher"
  return 0
  fi

  local output
  output="$(python3 - "$launcher" "$ROOT" <<'PY'
import json
import os
import subprocess
import sys

launcher = sys.argv[1]
root = sys.argv[2]

requests = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "qa-copilot", "version": "1.0"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "ck_validate", "arguments": {"content": "echo ok", "kind": "shell", "session_id": 1}}},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "ck_context", "arguments": {"session_id": 1}}},
    {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "ck_skill_list", "arguments": {}}},
]

payload = "\n".join(json.dumps(msg) for msg in requests) + "\n"
env = os.environ.copy()
env["CK_PROJECT_ROOT"] = root
env["LOGGER_LEVEL"] = "error"

try:
    completed = subprocess.run(
        [launcher],
        input=payload,
        capture_output=True,
        text=True,
        timeout=25,
        env=env,
        cwd=root,
    )
    output = (completed.stdout or "")[:20000]
    print(output, end="")
except subprocess.TimeoutExpired as exc:
    output = exc.stdout or ""
    if isinstance(output, bytes):
        output = output.decode("utf-8", errors="replace")
    print(output[:20000], end="")
PY
)"

  local missing=()
  for id in 1 2 3 4; do
  if [[ "$output" != *"\"id\":$id"* ]]; then
    missing+=("$id")
  fi
  done

  if [[ ${#missing[@]} -ne 0 ]]; then
  log "ERROR $launcher missing responses for ids: ${missing[*]}"
  return 1
  fi

  log "OK $launcher initialize + ck_validate + ck_context + ck_skill_list"
  return 0
}

probe_mcp_launcher "./bin/controlkeel-mcp"
probe_mcp_launcher "./controlkeel/bin/controlkeel-mcp"

if [[ "$RUN_FULL" -eq 1 ]]; then
  log ""
  log "== Attach matrix (system CLI) =="
  system_hosts=(copilot cursor codex-cli claude-code windsurf cline kiro augment opencode gemini-cli continue goose roo-code aider amp vscode)
  system_fail=0
  for h in "${system_hosts[@]}"; do
    if run_with_timeout /tmp/ck_attach_system.out "$CONTROLKEEL_BIN" attach "$h"; then
      log "PASS system $h"
    else
      log "FAIL system $h"
      tail -n 4 /tmp/ck_attach_system.out || true
      system_fail=$((system_fail + 1))
    fi
  done

  log ""
  log "== Attach matrix (local source via mix ck.attach) =="
  local_fail=0
  for h in "${system_hosts[@]}"; do
    if run_with_timeout /tmp/ck_attach_local.out mix ck.attach "$h"; then
      log "PASS local $h"
    else
      log "FAIL local $h"
      tail -n 6 /tmp/ck_attach_local.out || true
      local_fail=$((local_fail + 1))
    fi
  done

  log ""
  log "== Summary =="
  log "system attach failures: $system_fail"
  log "local attach failures: $local_fail"

  if [[ "$local_fail" -ne 0 ]]; then
    log "ERROR local source attach matrix has failures"
    exit 1
  fi

  if [[ "$system_fail" -ne 0 ]]; then
    log "WARN system release attach matrix has failures (check release parity / idempotency behavior)"
  fi
else
  log ""
  log "== Summary =="
  log "Skipping attach matrices by default. Use --full to include system/local host matrix checks."
fi

log "OK qa-copilot-parity completed"