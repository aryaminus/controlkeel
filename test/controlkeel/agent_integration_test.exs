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
    assert "cline" in ids
    assert "roo-code" in ids
    assert "goose" in ids
    assert "devin" in ids
    assert "vllm" in ids
    assert "huggingface" in ids
  end

  test "labels and targets are available for native-first agents" do
    claude = AgentIntegration.get("claude-code")
    codex = AgentIntegration.get("codex-cli")
    cline = AgentIntegration.get("cline")
    roo = AgentIntegration.get("roo-code")
    goose = AgentIntegration.get("goose")

    assert claude.label == "Claude Code"
    assert claude.support_class == "attach_client"
    assert claude.preferred_target == "claude-standalone"
    assert "claude-plugin" in claude.export_targets
    assert claude.auto_bootstrap

    assert claude.provider_bridge == %{
             supported: true,
             provider: "anthropic",
             mode: "env_bridge",
             owner: "agent"
           }

    assert codex.label == "Codex CLI"
    assert codex.support_class == "attach_client"
    assert codex.preferred_target == "codex"
    assert "open-standard" in codex.export_targets
    assert "project" in codex.supported_scopes
    assert "ck_validate" in codex.required_mcp_tools
    assert codex.auto_bootstrap

    assert codex.provider_bridge == %{
             supported: true,
             provider: "openai",
             mode: "env_bridge",
             owner: "agent"
           }

    assert cline.label == "Cline"
    assert cline.support_class == "attach_client"
    assert cline.preferred_target == "cline-native"
    assert cline.auth_mode == "ck_owned"
    assert cline.skills_mode == "native"
    assert "project" in cline.supported_scopes
    assert "ck_validate" in cline.required_mcp_tools

    assert roo.label == "Roo Code"
    assert roo.support_class == "attach_client"
    assert roo.preferred_target == "roo-native"
    assert roo.auth_mode == "ck_owned"
    assert roo.skills_mode == "native"
    assert roo.supported_scopes == ["project"]

    assert goose.label == "Goose"
    assert goose.support_class == "attach_client"
    assert goose.preferred_target == "goose-native"
    assert goose.auth_mode == "ck_owned"
    assert goose.skills_mode == "instructions_only"
    assert goose.supported_scopes == ["project"]
  end

  test "every integration references valid targets and install channels" do
    target_ids = SkillTarget.ids()

    Enum.each(AgentIntegration.catalog(), fn integration ->
      if integration.preferred_target do
        assert integration.preferred_target in target_ids
      end

      assert Enum.all?(integration.export_targets, &(&1 in target_ids))
      assert integration.install_channels != []
      assert is_boolean(integration.auto_bootstrap)
      assert is_map(integration.provider_bridge)

      if integration.support_class in ["framework_adapter", "provider_only", "unverified"] do
        assert integration.required_mcp_tools == []
      else
        assert integration.required_mcp_tools != []
      end

      if integration.support_class == "unverified" do
        assert integration.supported_scopes == []
      else
        assert integration.supported_scopes != []
      end
    end)
  end

  test "typed runtime, provider, and alias rows stay truthful" do
    devin = AgentIntegration.get("devin")
    codex_app = AgentIntegration.get("codex-app-server")
    vllm = AgentIntegration.get("vllm")

    assert devin.support_class == "headless_runtime"
    assert devin.runtime_export_command == "controlkeel runtime export devin"
    assert devin.preferred_target == "devin-runtime"

    assert codex_app.support_class == "alias"
    assert codex_app.alias_of == "codex-cli"

    assert vllm.support_class == "provider_only"
    assert vllm.preferred_target == "provider-profile"
    assert vllm.attach_command == nil
  end
end
