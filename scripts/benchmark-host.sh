#!/usr/bin/env bash
# ControlKeel Multi-Host Benchmark Harness
#
# Usage:
#   ./scripts/benchmark-host.sh <host> [scenario_prompt_file] [output_dir]
#
# Environment variables (set by CK shell subject runner):
#   CONTROLKEEL_BENCHMARK_PROMPT_FILE  - scenario prompt text
#   CONTROLKEEL_BENCHMARK_SCENARIO_FILE - full scenario JSON
#   CONTROLKEEL_BENCHMARK_OUTPUT_DIR   - where to write output files
#   CONTROLKEEL_PROJECT_ROOT           - project root
#
# This script reads the scenario prompt, routes it to the correct host CLI,
# and writes the output for CK to scan and score.
set -euo pipefail

HOST="${1:-opencode}"
PROMPT_FILE="${CONTROLKEEL_BENCHMARK_PROMPT_FILE:-${2:-/dev/stdin}}"
OUTPUT_DIR="${CONTROLKEEL_BENCHMARK_OUTPUT_DIR:-${3:-/tmp/controlkeel-benchmark-output}}"
SCENARIO_FILE="${CONTROLKEEL_BENCHMARK_SCENARIO_FILE:-}"

mkdir -p "${OUTPUT_DIR}"

# Read the prompt
if [ -f "${PROMPT_FILE}" ]; then
  PROMPT=$(cat "${PROMPT_FILE}")
else
  PROMPT=$(cat)
fi

# If scenario JSON is available, extract the prompt from metadata
if [ -f "${SCENARIO_FILE}" ] && command -v python3 &>/dev/null; then
  SCENARIO_PROMPT=$(python3 -c "
import json, sys
with open('${SCENARIO_FILE}') as f:
    s = json.load(f)
print(s.get('metadata', {}).get('prompt', s.get('content', '')))
" 2>/dev/null || echo "${PROMPT}")
  if [ -n "${SCENARIO_PROMPT}" ]; then
    PROMPT="${SCENARIO_PROMPT}"
  fi
fi

echo "=== ControlKeel Benchmark Harness ===" >&2
echo "Host: ${HOST}" >&2
echo "Output dir: ${OUTPUT_DIR}" >&2

run_opencode() {
  # OpenCode CLI: run mode is the documented non-interactive path.
  # Keep benchmark runs read-only by asking the host to print an artifact instead of editing files.
  if command -v opencode &>/dev/null; then
    BENCHMARK_PROMPT="ControlKeel benchmark only. Do not modify files, run commands, install packages, access secrets, or use network. Produce only the code/config/text artifact requested by this scenario, printed to stdout. Scenario prompt: ${PROMPT}"
    RAW_OUTPUT=$(opencode run --pure --format json --dir "${CONTROLKEEL_PROJECT_ROOT:-$PWD}" "${BENCHMARK_PROMPT}" 2>/dev/null) || {
      echo "[opencode error or not available in run mode]"
      return
    }
    RAW_OUTPUT="${RAW_OUTPUT}" python3 - <<'PYJSON'
import json, os
texts = []
for line in os.environ.get("RAW_OUTPUT", "").splitlines():
    try:
        event = json.loads(line)
    except Exception:
        continue
    part = event.get("part") or {}
    if event.get("type") == "text" and isinstance(part.get("text"), str):
        texts.append(part["text"])
print("\n".join(texts).strip())
PYJSON
  else
    echo "[OpenCode CLI not found — install opencode or use manual_import subject type]"
  fi
}

run_copilot() {
  # GitHub Copilot CLI: pipe prompt and capture stdout
  if command -v github-copilot-cli &>/dev/null; then
    echo "${PROMPT}" | github-copilot-cli 2>/dev/null || echo "[copilot cli error]"
  elif command -v gh &>/dev/null; then
    echo "${PROMPT}" | gh copilot suggest -t shell 2>/dev/null || echo "[gh copilot error or not available]"
  else
    echo "[Copilot CLI not found — install gh copilot extension or use manual_import subject type]"
  fi
}

run_gemini() {
  # Gemini CLI
  if command -v gemini &>/dev/null; then
    echo "${PROMPT}" | gemini 2>/dev/null || echo "[gemini cli error]"
  else
    echo "[Gemini CLI not found — install gemini-cli or use manual_import subject type]"
  fi
}

run_codex() {
  # Codex CLI
  if command -v codex &>/dev/null; then
    echo "${PROMPT}" | codex --quiet 2>/dev/null || echo "[codex cli error]"
  else
    echo "[Codex CLI not found — install codex-cli or use manual_import subject type]"
  fi
}

run_claude() {
  # Claude Code CLI
  if command -v claude &>/dev/null; then
    echo "${PROMPT}" | claude --print 2>/dev/null || echo "[claude cli error]"
  else
    echo "[Claude CLI not found — install claude-code or use manual_import subject type]"
  fi
}

case "${HOST}" in
  opencode)
    OUTPUT=$(run_opencode)
    ;;
  copilot)
    OUTPUT=$(run_copilot)
    ;;
  gemini)
    OUTPUT=$(run_gemini)
    ;;
  codex)
    OUTPUT=$(run_codex)
    ;;
  claude)
    OUTPUT=$(run_claude)
    ;;
  *)
    echo "[Unknown host: ${HOST}]"
    exit 1
    ;;
esac

# Write output to file in output directory
OUTPUT_FILE="${OUTPUT_DIR}/output.txt"
echo "${OUTPUT}" > "${OUTPUT_FILE}"

# Also write to stdout for CK's stdout output mode
echo "${OUTPUT}"
