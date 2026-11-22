defmodule ControlKeel.Skills.ClaudeHooks do
  @moduledoc false

  def write_hooks(root) do
    hooks_dir = Path.join(root, ".claude/hooks")
    File.mkdir_p!(hooks_dir)

    hooks = [
      {"permission-request.sh", permission_request_hook()},
      {"post-compact.sh", post_compact_hook()},
      {"pre-compact.sh", pre_compact_hook()},
      {"pre-tool-use-bash.sh", pre_tool_use_bash_hook()},
      {"pre-tool-use-write.sh", pre_tool_use_write_hook()},
      {"stop.sh", ControlKeel.Skills.Exporter.claude_stop_hook_contents()},
      {"user-prompt-submit.sh", user_prompt_submit_hook()}
    ]

    # Hooks earlier releases installed that only repeated static reminders
    # (or booted the CLI on every event). Remove them so an upgrade stops
    # firing them even when an older settings.json still references them.
    remove_retired_hooks(hooks_dir)

    paths =
      for {filename, content} <- hooks do
        path = Path.join(hooks_dir, filename)
        File.write!(path, content)
        File.chmod!(path, 0o755)
        %{"path" => path, "kind" => "hook"}
      end

    paths
  end

  @doc """
  Removes hook scripts earlier releases generated, but only when the file's
  contents show ControlKeel wrote it. A user script that happens to share a
  retired name is left alone.
  """
  def remove_retired_hooks(hooks_dir) do
    Enum.each(retired_hooks(), fn filename ->
      path = Path.join(hooks_dir, filename)

      with {:ok, contents} <- File.read(path),
           true <- ck_generated?(contents) do
        _ = File.rm(path)
      end
    end)
  end

  defp ck_generated?(contents) do
    String.starts_with?(contents, "#!/usr/bin/env sh") and
      Regex.match?(~r/ControlKeel|ck_context|ck_validate|ck_bin\(\)/, contents)
  end

  @doc false
  def retired_hooks do
    [
      "config-change.sh",
      "post-tool-batch.sh",
      "post-tool-use-bash.sh",
      "session-start.sh",
      "subagent-start.sh",
      "subagent-stop.sh",
      "task-created.sh",
      "task-completed.sh"
    ]
  end

  # Portable binary resolution shared by every hook that shells out:
  # CONTROLKEEL_BIN wins, then the repo-local bin/controlkeel shim, then
  # PATH. Never a bare `controlkeel` (breaks on GUI-launched hosts where
  # PATH lacks the install dir).
  defp ck_resolve do
    """
    ck_bin() {
      if [ -n "${CONTROLKEEL_BIN:-}" ] && [ -x "$CONTROLKEEL_BIN" ]; then printf '%s' "$CONTROLKEEL_BIN"; return 0; fi
      _root="${CK_PROJECT_ROOT:-}"
      if [ -z "$_root" ] && command -v git >/dev/null 2>&1; then _root=$(git rev-parse --show-toplevel 2>/dev/null || true); fi
      if [ -n "$_root" ] && [ -x "$_root/bin/controlkeel" ]; then printf '%s' "$_root/bin/controlkeel"; return 0; fi
      if command -v controlkeel >/dev/null 2>&1; then command -v controlkeel; return 0; fi
      return 1
    }
    """
  end

  defp permission_request_hook do
    """
    #!/usr/bin/env sh
    #{ck_resolve()}
    BIN=$(ck_bin) || exit 0
    "$BIN" review plan submit --stdin --submitted-by claude-code
    """
  end

  defp post_compact_hook do
    """
    #!/usr/bin/env sh
    printf '{"systemMessage":"Context was compacted. You are in a ControlKeel-governed session: always call ck_context before proceeding, ck_validate before code or shell changes, and ck_finding for any issues you discover."}'
    """
  end

  defp pre_compact_hook do
    """
    #!/usr/bin/env sh
    printf '{"systemMessage":"Context compaction is about to run. Preserve the active ControlKeel gate, approved decisions, blocked findings, proof obligations, and next valid action in the compacted summary."}'
    """
  end

  defp pre_tool_use_bash_hook do
    """
    #!/usr/bin/env sh
    TOOL_INPUT=$(cat)
    if command -v jq >/dev/null 2>&1; then
      CMD=$(printf '%s' "$TOOL_INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null)
    else
      CMD=$(printf '%s' "$TOOL_INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command") or d.get("command", ""))' 2>/dev/null || true)
    fi
    printf '%s' "$CMD" | grep -qE '(^|[;&|(][[:space:]]*)(fly[[:space:]]+deploy|wrangler[[:space:]]+(deploy|publish)|docker[[:space:]]+push|git[[:space:]]+push|heroku[[:space:]]|kubectl[[:space:]]+apply|terraform[[:space:]]+apply|vercel[[:space:]]+(deploy|--prod)|netlify[[:space:]]+deploy)' && printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Deploy-like command detected. Confirm ck_validate and ck_review_submit were called this turn before proceeding."}}' || true
    """
  end

  defp pre_tool_use_write_hook do
    """
    #!/usr/bin/env sh
    fp=$(cat | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)
    [ -z "$fp" ] && exit 0
    printf '%s' "$fp" | grep -qiE '(\\.env$|credentials|secret|\\.pem$|\\.key$|id_rsa|passw)' && printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Writing to potentially sensitive file: %s. Verify ck_validate approved this change."}}\\n' "$fp" || true
    """
  end

  defp user_prompt_submit_hook do
    """
    #!/usr/bin/env sh
    input=$(cat)
    prompt=$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("prompt",""))' 2>/dev/null || echo "")
    [ -z "$prompt" ] && exit 0
    printf '%s' "$prompt" | grep -qE '(AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|BEGIN (RSA|OPENSSH|PGP) PRIVATE KEY)' && printf '{"decision":"block","reason":"Potential secret in prompt. Remove credentials before continuing."}'
    exit 0
    """
  end
end
