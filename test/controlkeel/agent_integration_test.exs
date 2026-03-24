defmodule ControlKeel.AgentIntegrationTest do
  use ExUnit.Case, async: true

  alias ControlKeel.AgentIntegration
  alias ControlKeel.Skills.SkillTarget

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
    assert claude.auto_bootstrap

    assert claude.provider_bridge == %{
             supported: true,
             provider: "anthropic",
             mode: "environment"
           }

    assert codex.label == "Codex CLI"
    assert codex.preferred_target == "codex"
    assert "open-standard" in codex.export_targets
    assert "project" in codex.supported_scopes
    assert "ck_validate" in codex.required_mcp_tools
    assert codex.auto_bootstrap
    assert codex.provider_bridge == %{supported: true, provider: "openai", mode: "environment"}
  end

  test "every integration references valid targets and install channels" do
    target_ids = SkillTarget.ids()

    Enum.each(AgentIntegration.catalog(), fn integration ->
      assert integration.preferred_target in target_ids
      assert Enum.all?(integration.export_targets, &(&1 in target_ids))
      assert integration.install_channels != []
      assert integration.required_mcp_tools != []
      assert integration.supported_scopes != []
      assert is_boolean(integration.auto_bootstrap)
      assert is_map(integration.provider_bridge)
    end)
  end
end
