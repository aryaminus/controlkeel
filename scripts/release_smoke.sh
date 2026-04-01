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
HOME_DIR="$TMP_DIR/home"
PORT=4081
DB_PATH="$TMP_DIR/controlkeel.db"
SECRET_KEY_BASE="controlkeel-release-smoke-secret"
SECRET_KEY_BASE="${SECRET_KEY_BASE}$(printf '0123456789abcdef0123456789abcdef0123456789abcdef')"
SERVER_LOG="$TMP_DIR/server.log"

mkdir -p "$HOME_DIR"
export HOME="$HOME_DIR"
export CONTROLKEEL_HOME="$HOME_DIR"
export DATABASE_PATH="$DB_PATH"
export SECRET_KEY_BASE="$SECRET_KEY_BASE"

cleanup() {
  if [ "${STARTED:-0}" -eq 1 ] && [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

run_command() {
  python3 - "$@" <<'PY'
import subprocess
import sys

argv = sys.argv[1:]
completed = subprocess.run(argv, capture_output=True, timeout=60, check=True)
sys.stdout.buffer.write(completed.stdout)
sys.stderr.buffer.write(completed.stderr)
PY
}

run_command "$BINARY" version >/dev/null
PHX_SERVER=true DATABASE_PATH="$DB_PATH" SECRET_KEY_BASE="$SECRET_KEY_BASE" PORT="$PORT" "$BINARY" serve >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
STARTED=1

sleep 1
if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
  echo "serve start failed" >&2
  if [ -f "$SERVER_LOG" ]; then
    echo "--- server log ---" >&2
    cat "$SERVER_LOG" >&2
  fi
  exit 1
fi

for _ in $(seq 1 20); do
  if curl --connect-timeout 1 --max-time 2 -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
    STARTED=0
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
