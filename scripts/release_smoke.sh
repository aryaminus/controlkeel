#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /absolute/path/to/controlkeel-binary" >&2
  exit 1
fi

BINARY=$1
TMP_DIR=$(mktemp -d)
PORT=4081
DB_PATH="$TMP_DIR/controlkeel.db"
SECRET_KEY_BASE="controlkeel-release-smoke-secret"

cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

"$BINARY" help >/dev/null
"$BINARY" version >/dev/null

(
  cd "$TMP_DIR"
  DATABASE_PATH="$DB_PATH" SECRET_KEY_BASE="$SECRET_KEY_BASE" "$BINARY" init >/dev/null
)

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

DATABASE_PATH="$DB_PATH" SECRET_KEY_BASE="$SECRET_KEY_BASE" PORT="$PORT" "$BINARY" serve &
SERVER_PID=$!

for _ in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
    exit 0
  fi

  sleep 1
done

echo "server smoke check failed" >&2
exit 1
