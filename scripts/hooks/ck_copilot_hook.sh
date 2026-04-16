#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
event=""
log_file="${CK_HOOK_LOG_FILE:-./tmp/ck-vscode-hooks.log}"

if echo "$payload" | grep -Eq '"hook(EventName|_event_name)"[[:space:]]*:[[:space:]]*"PreToolUse"'; then
  event="PreToolUse"
elif echo "$payload" | grep -Eq '"hook(EventName|_event_name)"[[:space:]]*:[[:space:]]*"PostToolUse"'; then
  event="PostToolUse"
elif echo "$payload" | grep -Eq '"hook(EventName|_event_name)"[[:space:]]*:[[:space:]]*"SessionStart"'; then
  event="SessionStart"
elif echo "$payload" | grep -Eq '"hook(EventName|_event_name)"[[:space:]]*:[[:space:]]*"UserPromptSubmit"'; then
  event="UserPromptSubmit"
elif echo "$payload" | grep -Eq '"hook(EventName|_event_name)"[[:space:]]*:[[:space:]]*"SubagentStart"'; then
  event="SubagentStart"
elif echo "$payload" | grep -Eq '"hook(EventName|_event_name)"[[:space:]]*:[[:space:]]*"SubagentStop"'; then
  event="SubagentStop"
elif echo "$payload" | grep -Eq '"hook(EventName|_event_name)"[[:space:]]*:[[:space:]]*"PreCompact"'; then
  event="PreCompact"
elif echo "$payload" | grep -Eq '"hook(EventName|_event_name)"[[:space:]]*:[[:space:]]*"Stop"'; then
  event="Stop"
fi

# Record runtime hook activity so VS Code lifecycle execution can be verified.
mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
payload_snippet="$(echo "$payload" | tr '\n' ' ' | cut -c1-240)"
printf '%s\t%s\t%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "${event:-unknown}" "$payload_snippet" >> "$log_file" 2>/dev/null || true

# Keep this lightweight: collect status context when available but do not block on failures.
controlkeel status >/dev/null 2>&1 || true

if [[ "$event" == "PreToolUse" ]]; then
  if [[ "$payload" == *"rm -rf"* ]] || [[ "$payload" == *"git reset --hard"* ]]; then
    cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked by ControlKeel safety policy: destructive command pattern detected"
  }
}
JSON
    exit 0
  fi

  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "ControlKeel governance checkpoint for tool execution"
  }
}
JSON
  exit 0
fi

if [[ "$event" == "SessionStart" ]]; then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "ControlKeel governance active: run ck_context/ck_validate before risky operations"
  }
}
JSON
  exit 0
fi

if [[ "$event" == "SubagentStart" ]]; then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "ControlKeel governance active for subagent: preserve findings/proof context"
  }
}
JSON
  exit 0
fi

cat <<'JSON'
{
  "continue": true,
  "systemMessage": "ControlKeel hook executed"
}
JSON
