#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /absolute/path/to/controlkeel-binary" >&2
  exit 1
fi

resolve_binary_path() {
  python3 - "$1" <<'PY'
import os
import sys

print(os.path.abspath(sys.argv[1]))
PY
}

BINARY=$(resolve_binary_path "$1")

if [ ! -f "$BINARY" ]; then
  echo "binary not found: $BINARY" >&2
  exit 1
fi

if [ ! -x "$BINARY" ]; then
  chmod +x "$BINARY"
fi

TMP_DIR=$(mktemp -d)
PORT=4081
DB_PATH="$TMP_DIR/controlkeel.db"
SECRET_KEY_BASE="controlkeel-release-smoke-secret"
SECRET_KEY_BASE="${SECRET_KEY_BASE}$(printf '0123456789abcdef0123456789abcdef0123456789abcdef')"
SERVER_LOG="$TMP_DIR/server.log"

cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

run_command() {
  python3 - "$@" <<'PY'
import subprocess
import sys

argv = sys.argv[1:]
completed = subprocess.run(argv, capture_output=True, timeout=30, check=True)
sys.stdout.buffer.write(completed.stdout)
sys.stderr.buffer.write(completed.stderr)
PY
}

run_command "$BINARY" help >/dev/null
run_command "$BINARY" version >/dev/null

python3 - "$BINARY" "$TMP_DIR" "$DB_PATH" "$SECRET_KEY_BASE" <<'PY'
import os
import subprocess
import sys

binary, tmp_dir, db_path, secret = sys.argv[1:5]
env = os.environ.copy()
env["DATABASE_PATH"] = db_path
env["SECRET_KEY_BASE"] = secret
completed = subprocess.run(
    [binary, "init", "--no-attach"],
    cwd=tmp_dir,
    env=env,
    timeout=60,
    check=False,
    capture_output=True,
)
if completed.returncode != 0:
    sys.stdout.buffer.write(completed.stdout)
    sys.stderr.buffer.write(completed.stderr)
    raise SystemExit(completed.returncode)
PY

test -f "$TMP_DIR/controlkeel/project.json"
test -f "$TMP_DIR/controlkeel/bin/controlkeel-mcp"

python3 - "$BINARY" "$TMP_DIR" <<'PY'
import json
import subprocess
import sys

binary, project_root = sys.argv[1:3]
request = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}
payload = json.dumps(request)
frame = f"Content-Length: {len(payload)}\r\n\r\n{payload}".encode()
completed = subprocess.run(
    [binary, "mcp", "--project-root", project_root],
    input=frame,
    capture_output=True,
    timeout=10,
    check=True,
)
stdout = completed.stdout.decode()
if "Content-Length:" not in stdout or "\"result\"" not in stdout:
    raise SystemExit("mcp initialize smoke check failed")
PY

DATABASE_PATH="$DB_PATH" SECRET_KEY_BASE="$SECRET_KEY_BASE" PORT="$PORT" "$BINARY" serve >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 20); do
  if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
    exit 0
  fi

  sleep 1
done

echo "server smoke check failed" >&2
if [ -f "$SERVER_LOG" ]; then
  echo "--- server log ---" >&2
  cat "$SERVER_LOG" >&2
fi
exit 1
