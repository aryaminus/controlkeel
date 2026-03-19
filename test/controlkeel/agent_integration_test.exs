defmodule ControlKeel.AgentIntegrationTest do
  use ExUnit.Case, async: true

  alias ControlKeel.AgentIntegration

  test "catalog exposes the supported attach matrix" do
    ids = Enum.map(AgentIntegration.catalog(), & &1.id)

    assert "claude-code" in ids
    assert "codex-cli" in ids
    assert "vscode" in ids
    assert "copilot" in ids
    assert "cursor" in ids
    assert "aider" in ids
  end

  test "labels and targets are available for native-first agents" do
    claude = AgentIntegration.get("claude-code")
    codex = AgentIntegration.get("codex-cli")

    assert claude.label == "Claude Code"
    assert claude.preferred_target == "claude-standalone"
    assert "claude-plugin" in claude.export_targets

    assert codex.label == "Codex CLI"
    assert codex.preferred_target == "codex"
    assert "open-standard" in codex.export_targets
  end
end
