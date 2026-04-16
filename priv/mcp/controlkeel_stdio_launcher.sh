#!/usr/bin/env sh
set -eu

export CK_MCP_MODE="${CK_MCP_MODE:-1}"
# Suppress Mix compile / task chatter on stdout before ck.mcp runs (stdio JSON-RPC).
export MIX_QUIET="${MIX_QUIET:-1}"
export MIX_ENV="${MIX_ENV:-dev}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# Cursor / OpenCode / Copilot MCP hosts set CK_PROJECT_ROOT to the governed workspace.
PROJECT_ROOT="${CK_PROJECT_ROOT:-$(/bin/pwd -P)}"

# Resolve the ControlKeel Elixir checkout when this script is either:
#   <repo>/bin/controlkeel-mcp           -> checkout is SCRIPT_DIR/..
#   <repo>/controlkeel/bin/controlkeel-mcp -> checkout is SCRIPT_DIR/../..
CK_SOURCE_ROOT=""
for _rel in .. ../..; do
  _cand=$(CDPATH= cd -- "$SCRIPT_DIR/$_rel" && pwd)
  if [ -f "$_cand/mix.exs" ] && [ -f "$_cand/lib/controlkeel/application.ex" ]; then
    CK_SOURCE_ROOT=$_cand
    break
  fi
done

exec_mix_ck_mcp_filtered() {
  fifo=$(mktemp "${TMPDIR:-/tmp}/controlkeel-mcp.XXXXXX")
  rm -f "$fifo"
  mkfifo "$fifo"

  cleanup() {
    rm -f "$fifo"
  }

  trap cleanup EXIT HUP INT TERM

  mix ck.mcp --project-root "$PROJECT_ROOT" "$@" <&0 >"$fifo" &
  mix_pid=$!

  awk '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)

      if (line ~ /^[\{\[]/) {
        print $0
        fflush()
      }
    }
  ' <"$fifo"
  awk_status=$?

  wait "$mix_pid"
  mix_status=$?

  cleanup
  trap - EXIT HUP INT TERM

  if [ "$mix_status" -ne 0 ]; then
    exit "$mix_status"
  fi

  exit "$awk_status"
}

# Optional: force a specific `controlkeel` executable (must support `mcp`, e.g. Burrito
# build or a wrapper). Do **not** point at `_build/.../rel/.../bin/controlkeel` from
# `mix release` alone — that script only knows start/eval/remote/etc., not `mcp`.
if [ -n "${CONTROLKEEL_BIN:-}" ]; then
  exec "$CONTROLKEEL_BIN" mcp --project-root "$PROJECT_ROOT" "$@"
fi

# ControlKeel *source* tree: always `mix ck.mcp` so MCP matches your checkout.
if [ -n "$CK_SOURCE_ROOT" ]; then
  cd "$CK_SOURCE_ROOT"
  exec_mix_ck_mcp_filtered "$@"
fi

# Governed projects without a checkout: use the installed CLI.
if command -v controlkeel >/dev/null 2>&1; then
  exec controlkeel mcp --project-root "$PROJECT_ROOT" "$@"
fi

echo "controlkeel MCP launcher could not find a ControlKeel mix checkout or controlkeel on PATH" >&2
exit 1
