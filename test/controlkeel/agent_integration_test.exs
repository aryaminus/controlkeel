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
    assert "augment" in ids
    assert "pi" in ids
    assert "devin" in ids
    assert "dmux" in ids
    assert "virtual-bash" in ids
    assert "vllm" in ids
    assert "huggingface" in ids
    assert "codex" in ids
    assert "gemini" in ids
    assert "kiro-cli" in ids
    assert "roo" in ids
    assert "jcode" in ids
    assert "antigravity" in ids
    assert "clawdbot" in ids
    assert "kilo" in ids
    assert "nous-research" in ids
    assert "trae" in ids
  end

  test "labels and targets are available for native-first agents" do
    claude = AgentIntegration.get("claude-code")
    codex = AgentIntegration.get("codex-cli")
    cline = AgentIntegration.get("cline")
    roo = AgentIntegration.get("roo-code")
    goose = AgentIntegration.get("goose")
    pi = AgentIntegration.get("pi")
    windsurf = AgentIntegration.get("windsurf")
    continue = AgentIntegration.get("continue")
    cursor = AgentIntegration.get("cursor")
    gemini = AgentIntegration.get("gemini-cli")
    kiro = AgentIntegration.get("kiro")
    amp = AgentIntegration.get("amp")
    augment = AgentIntegration.get("augment")
    aider = AgentIntegration.get("aider")
    conductor = AgentIntegration.get("conductor")
    conductor_web = AgentIntegration.get("conductor-web")
    dmux = AgentIntegration.get("dmux")

    assert claude.label == "Claude Code"
    assert claude.support_class == "attach_client"
    assert claude.preferred_target == "claude-standalone"
    assert "claude-plugin" in claude.export_targets
    assert claude.auto_bootstrap
    assert claude.phase_model == "host_plan_mode"
    assert claude.browser_embed == "external"
    assert claude.subagent_visibility == "primary_only"
    assert claude.runtime_transport == "claude_agent_sdk"
    assert claude.runtime_auth_owner == "agent"
    assert claude.runtime_review_transport == "hook_sdk"
    assert claude.runtime_session_support["fork"]

    assert Enum.any?(
             claude.package_outputs,
             &(&1["artifact"] == "controlkeel-claude-plugin.tar.gz")
           )

    assert Enum.any?(
             claude.direct_install_methods,
             &(&1["command"] == "controlkeel plugin install claude")
           )

    assert Enum.any?(
             claude.direct_install_methods,
             &(&1["command"] == "claude --plugin-dir ./controlkeel/dist/claude-plugin")
           )

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
    assert codex.phase_model == "review_only"
    assert codex.review_experience == "browser_review"
    assert codex.submission_mode == "command"
    assert codex.runtime_transport == "codex_sdk"
    assert codex.runtime_auth_owner == "agent"
    assert codex.auth_mode == "agent_runtime"
    assert ".codex/skills" in codex.artifact_surfaces
    assert ".codex/config.toml" in codex.artifact_surfaces
    assert ".codex/commands/controlkeel-review.md" in codex.artifact_surfaces
    refute codex.runtime_session_support["fork"]

    assert codex.provider_bridge == %{
             supported: true,
             provider: "openai",
             mode: "agent_runtime",
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
    assert goose.skills_mode == "native"
    assert goose.supported_scopes == ["project"]

    assert pi.label == "Pi"
    assert pi.preferred_target == "pi-native"
    assert pi.install_experience == "first_class"
    assert pi.review_experience == "browser_review"
    assert pi.submission_mode == "command"
    assert pi.phase_model == "file_plan_mode"
    assert pi.auth_mode == "agent_runtime"
    assert pi.runtime_transport == "pi_rpc"
    assert pi.runtime_review_transport == "extension_rpc"
    assert ".pi/commands/controlkeel-review.md" in pi.artifact_surfaces
    assert ".pi/commands/controlkeel-submit-plan.md" in pi.artifact_surfaces
    assert ".pi/mcp.json" in pi.artifact_surfaces
    assert Enum.any?(pi.direct_install_methods, &(&1["command"] =~ "pi install npm:"))

    assert windsurf.review_experience == "native_review"
    assert windsurf.submission_mode == "hook"
    assert "hooks" in windsurf.agent_uses_ck_via
    assert ".windsurf/hooks.json" in windsurf.artifact_surfaces
    assert ".windsurf/hooks" in windsurf.artifact_surfaces

    assert continue.submission_mode == "command"
    assert ".continue/mcpServers/controlkeel.yaml" in continue.artifact_surfaces

    opencode = AgentIntegration.get("opencode")
    assert opencode.support_class == "attach_client"
    assert opencode.preferred_target == "opencode-native"
    assert ".opencode/skills" in opencode.artifact_surfaces
    assert ".agents/skills" in opencode.artifact_surfaces
    assert ".opencode/plugins/controlkeel-governance.ts" in opencode.artifact_surfaces

    letta = AgentIntegration.get("letta-code")
    assert letta.support_class == "attach_client"
    assert letta.preferred_target == "letta-code-native"
    assert letta.skills_mode == "native"
    assert letta.mcp_mode == "native"
    assert letta.review_experience == "native_review"
    assert "hooks" in letta.agent_uses_ck_via
    assert ".letta/settings.json" in letta.artifact_surfaces
    assert ".letta/controlkeel-mcp.sh" in letta.artifact_surfaces
    assert ".agents/skills" in letta.artifact_surfaces

    assert Enum.any?(
             letta.direct_install_methods,
             &(&1["command"] == "npm install -g @letta-ai/letta-code")
           )

    assert cursor.submission_mode == "command"
    assert ".cursor/background-agents" in cursor.artifact_surfaces
    assert ".cursor/skills" in cursor.artifact_surfaces
    assert ".cursor/agents" in cursor.artifact_surfaces
    assert "hooks" in cursor.agent_uses_ck_via
    assert "plugin" in cursor.agent_uses_ck_via

    assert gemini.phase_model == "review_only"
    assert ".gemini/commands/controlkeel" in gemini.artifact_surfaces

    assert kiro.review_experience == "native_review"
    assert ".kiro/settings" in kiro.artifact_surfaces

    kilo = AgentIntegration.get("kilo")
    assert kilo.support_class == "attach_client"
    assert kilo.preferred_target == "kilo-native"
    assert kilo.auth_mode == "ck_owned"
    assert kilo.skills_mode == "native"
    assert ".kilo/skills" in kilo.artifact_surfaces
    assert ".kilo/commands" in kilo.artifact_surfaces
    assert ".kilo/kilo.json" in kilo.artifact_surfaces
    assert Enum.any?(kilo.direct_install_methods, &(&1["command"] == "controlkeel attach kilo"))

    assert amp.review_experience == "native_review"
    assert amp.submission_mode == "tool_call"
    assert "native_skills" in amp.agent_uses_ck_via
    assert ".agents/skills/controlkeel-governance" in amp.artifact_surfaces
    assert ".amp/commands" in amp.artifact_surfaces

    assert Enum.any?(
             amp.direct_install_methods,
             &(&1["command"] ==
                 "amp skill add ./controlkeel/dist/amp-native/.agents/skills/controlkeel-governance")
           )

    assert augment.label == "Augment / Auggie CLI"
    assert augment.preferred_target == "augment-native"
    assert augment.install_experience == "first_class"
    assert augment.review_experience == "native_review"
    assert augment.submission_mode == "hook"
    assert augment.phase_model == "host_plan_mode"
    assert augment.auth_mode == "agent_runtime"
    assert augment.runtime_transport == "auggie_sdk_acp"
    assert augment.runtime_auth_owner == "agent"
    assert augment.runtime_review_transport == "plugin_hook_acp"
    assert augment.runtime_session_support["create"]
    assert augment.runtime_session_support["resume"]
    refute augment.runtime_session_support["fork"]
    assert ".augment/commands/controlkeel-review.md" in augment.artifact_surfaces
    assert ".augment-plugin/plugin.json" in augment.artifact_surfaces
    assert "hooks/hooks.json" in augment.artifact_surfaces
    assert "hooks" in augment.agent_uses_ck_via
    assert "plugin" in augment.agent_uses_ck_via

    assert Enum.any?(
             augment.direct_install_methods,
             &(&1["command"] == "npm install -g @augmentcode/auggie")
           )

    assert Enum.any?(
             augment.direct_install_methods,
             &(&1["command"] == "auggie --plugin-dir ./controlkeel/dist/augment-plugin")
           )

    assert Enum.any?(
             augment.package_outputs,
             &(&1["artifact"] == "controlkeel-augment-plugin.tar.gz")
           )

    assert aider.phase_model == "review_only"
    assert aider.submission_mode == "command"
    assert "AIDER.md" in aider.artifact_surfaces

    droid = AgentIntegration.get("droid")
    assert droid.preferred_target == "droid-bundle"
    assert "droid-plugin" in droid.export_targets
    assert "native_skills" in droid.agent_uses_ck_via
    assert "commands" in droid.agent_uses_ck_via
    assert "plugin" in droid.agent_uses_ck_via
    assert ".factory/skills" in droid.artifact_surfaces
    assert ".factory/droids" in droid.artifact_surfaces
    assert ".factory/commands" in droid.artifact_surfaces
    assert ".factory-plugin/plugin.json" in droid.artifact_surfaces
    assert "mcp.json" in droid.artifact_surfaces

    assert conductor.support_class == "framework_adapter"
    assert conductor.preferred_target == "claude-standalone"
    assert conductor.mcp_mode == "native"
    assert conductor.skills_mode == "native"
    assert conductor.agent_uses_ck_via == ["local_mcp", "native_skills", "commands"]
    assert ".mcp.json" in conductor.artifact_surfaces
    assert "CLAUDE.md" in conductor.artifact_surfaces
    assert ".claude/commands" in conductor.artifact_surfaces
    assert conductor.execution_support == "inbound_only"
    assert conductor.ck_runs_agent_via == "none"

    assert conductor.provider_bridge == %{
             supported: true,
             provider: "anthropic",
             mode: "env_bridge",
             owner: "agent"
           }

    paperclip = AgentIntegration.get("paperclip")

    assert paperclip.support_class == "framework_adapter"
    assert paperclip.agent_uses_ck_via == ["local_mcp", "native_skills", "commands", "plugin"]
    assert "~/.paperclip/instances/default/config.json" in paperclip.artifact_surfaces
    assert paperclip.mcp_mode == "native"
    assert paperclip.skills_mode == "native"
    assert paperclip.execution_support == "inbound_only"
    assert paperclip.ck_runs_agent_via == "none"
    assert paperclip.preferred_target == "framework-adapter"
    assert paperclip.provider_bridge == %{supported: false, mode: "none", owner: "none"}

    assert dmux.support_class == "framework_adapter"
    assert dmux.agent_uses_ck_via == ["local_mcp", "native_skills", "commands", "hooks"]
    assert ".dmux-hooks/" in dmux.artifact_surfaces
    assert ".dmux.defaults.json" in dmux.artifact_surfaces
    assert ".dmux/worktrees/" in dmux.artifact_surfaces
    assert dmux.mcp_mode == "native"
    assert dmux.skills_mode == "native"
    assert dmux.execution_support == "inbound_only"
    assert dmux.ck_runs_agent_via == "none"
    assert dmux.preferred_target == "framework-adapter"
    assert dmux.provider_bridge == %{supported: false, mode: "none", owner: "none"}
    assert dmux.phase_model == "host_plan_mode"
    assert dmux.review_experience == "browser_review"
    assert dmux.submission_mode == "command"
    assert dmux.feedback_mode == "command_reply"

    assert Enum.any?(dmux.direct_install_methods, &(&1["command"] == "npm -g i dmux"))

    assert Enum.any?(
             dmux.direct_install_methods,
             &(&1["command"] == "controlkeel attach codex-cli")
           )

    assert conductor_web.support_class == "alias"
    assert conductor_web.alias_of == "conductor"
    assert conductor_web.preferred_target == "claude-standalone"

    openclaw = AgentIntegration.get("openclaw")

    assert Enum.any?(
             openclaw.direct_install_methods,
             &(&1["command"] == "controlkeel plugin install openclaw")
           )

    codex_alias = AgentIntegration.get("codex")
    t3code = AgentIntegration.get("t3code")
    gemini_alias = AgentIntegration.get("gemini")
    kiro_cli_alias = AgentIntegration.get("kiro-cli")
    roo_alias = AgentIntegration.get("roo")

    assert codex_alias.support_class == "alias"
    assert codex_alias.alias_of == "codex-cli"
    assert codex_alias.auth_mode == "agent_runtime"
    assert codex_alias.preferred_target == "codex"

    assert t3code.support_class == "attach_client"
    assert t3code.attach_command == "controlkeel attach codex-cli"
    assert t3code.preferred_target == "codex"
    assert t3code.auth_mode == "agent_runtime"
    assert t3code.phase_model == "review_only"
    assert t3code.submission_mode == "tool_call"
    assert t3code.feedback_mode == "tool_call"
    assert t3code.runtime_transport == "t3code_provider_runtime"
    assert t3code.runtime_review_transport == "orchestration_domain_event"
    assert t3code.runtime_session_support["fork"]
    assert ".codex/skills" in t3code.artifact_surfaces
    assert t3code.runtime_capabilities[:policy_gate] == true
    assert t3code.runtime_capabilities[:tool_approval] == true
    assert t3code.runtime_capabilities[:deterministic_event_ids] == true
    assert t3code.runtime_capabilities[:replay_safe_delivery] == true

    assert gemini_alias.support_class == "alias"
    assert gemini_alias.alias_of == "gemini-cli"
    assert gemini_alias.preferred_target == "gemini-cli-native"

    assert kiro_cli_alias.support_class == "alias"
    assert kiro_cli_alias.alias_of == "kiro"

    assert roo_alias.support_class == "alias"
    assert roo_alias.alias_of == "roo-code"
  end

  test "skills-compatible agent names stay honest about support tier" do
    jcode = AgentIntegration.get("jcode")
    antigravity = AgentIntegration.get("antigravity")
    clawdbot = AgentIntegration.get("clawdbot")
    nous = AgentIntegration.get("nous-research")
    trae = AgentIntegration.get("trae")

    assert jcode.support_class == "unverified"
    assert jcode.preferred_target == "instructions-only"
    assert jcode.export_targets == ["instructions-only"]
    assert jcode.agent_uses_ck_via == ["local_mcp"]
    assert jcode.mcp_mode == "native"
    assert jcode.skills_mode == "instructions_only"
    assert "AGENTS.md" in jcode.artifact_surfaces
    assert ".jcode/mcp.json" in jcode.artifact_surfaces
    assert ".jcode/prompt-overlay.md" in jcode.artifact_surfaces
    assert jcode.required_mcp_tools == []

    assert Enum.any?(
             jcode.direct_install_methods,
             &(&1["command"] =~
                 "raw.githubusercontent.com/1jehuang/jcode/master/scripts/install.sh")
           )

    for integration <- [antigravity, clawdbot, nous, trae] do
      assert integration.support_class == "unverified"
      assert integration.preferred_target == "open-standard"
      assert integration.export_targets == ["open-standard"]
      assert integration.agent_uses_ck_via == ["native_skills"]
      assert integration.skills_mode == "native"
      assert integration.required_mcp_tools == []

      assert Enum.any?(
               integration.direct_install_methods,
               &(&1["command"] ==
                   "npx skills add https://github.com/aryaminus/controlkeel --skill controlkeel-governance")
             )
    end
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
      assert integration.install_experience in ["first_class", "guided", "fallback"]

      assert integration.review_experience in [
               "native_review",
               "browser_review",
               "feedback_only",
               "none"
             ]

      assert integration.submission_mode in [
               "tool_call",
               "hook",
               "command",
               "file_watch",
               "manual"
             ]

      assert integration.feedback_mode in ["tool_call", "file_patch", "command_reply", "manual"]
      assert integration.confidence_level in ["shipped", "experimental", "research"]
      assert integration.phase_model in ["host_plan_mode", "file_plan_mode", "review_only"]
      assert integration.browser_embed in ["external", "vscode_webview", "none"]
      assert integration.subagent_visibility in ["primary_only", "all", "none"]
      assert is_binary(integration.runtime_transport) or is_nil(integration.runtime_transport)
      assert is_binary(integration.runtime_auth_owner) or is_nil(integration.runtime_auth_owner)

      assert is_binary(integration.runtime_review_transport) or
               is_nil(integration.runtime_review_transport)

      assert is_map(integration.runtime_session_support)
      assert is_map(integration.runtime_capabilities)
      assert is_list(integration.plan_phase_support)
      assert is_list(integration.artifact_surfaces)
      assert is_list(integration.package_outputs)
      assert is_list(integration.direct_install_methods)
      assert is_map(integration.experience_profile)

      assert integration.experience_profile.cost in [
               "local_free",
               "host_subscription_or_agent_metered",
               "ck_budget_metered",
               "workspace_subscription",
               "provider_metered",
               "unknown"
             ]

      assert integration.experience_profile.performance in [
               "interactive_direct",
               "human_handoff",
               "background_runtime",
               "provider_backend",
               "adapter_dependent",
               "unknown",
               "manual"
             ]

      assert integration.experience_profile.token_pressure in [
               "host_quota_sensitive",
               "workspace_quota_sensitive",
               "ck_budget_sensitive",
               "provider_context_window",
               "unknown"
             ]

      assert integration.experience_profile.time in [
               "fast_feedback",
               "checkpoint_driven",
               "long_running_ok",
               "manual_research",
               "manual"
             ]

      assert integration.experience_profile.ux in [
               "native_governed",
               "browser_review",
               "guided_feedback",
               "runtime_export",
               "provider_configuration",
               "research_only",
               "manual"
             ]

      if integration.support_class in ["framework_adapter", "provider_only", "unverified"] do
        assert integration.required_mcp_tools == []
      else
        assert integration.required_mcp_tools != []
      end

      if integration.runtime_capabilities != %{} do
        assert Map.has_key?(integration.runtime_capabilities, :policy_gate)
        assert Map.has_key?(integration.runtime_capabilities, :tool_approval)
        assert Map.has_key?(integration.runtime_capabilities, :deterministic_event_ids)
        assert Map.has_key?(integration.runtime_capabilities, :replay_safe_delivery)
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
    executor = AgentIntegration.get("executor")
    virtual_bash = AgentIntegration.get("virtual-bash")
    codex_app = AgentIntegration.get("codex-app-server")
    vllm = AgentIntegration.get("vllm")
    vscode = AgentIntegration.get("vscode")
    opencode = AgentIntegration.get("opencode")
    copilot = AgentIntegration.get("copilot")

    assert devin.support_class == "headless_runtime"
    assert devin.runtime_export_command == "controlkeel runtime export devin"
    assert devin.preferred_target == "devin-runtime"
    assert executor.support_class == "headless_runtime"
    assert executor.runtime_export_command == "controlkeel runtime export executor"
    assert executor.preferred_target == "executor-runtime"
    assert virtual_bash.support_class == "headless_runtime"
    assert virtual_bash.runtime_export_command == "controlkeel runtime export virtual-bash"
    assert virtual_bash.preferred_target == "virtual-bash-runtime"
    assert AgentIntegration.get("letta-code").execution_support == "direct"

    assert codex_app.support_class == "attach_client"
    assert codex_app.attach_command == "controlkeel attach codex-cli"
    assert codex_app.runtime_transport == "codex_app_server_json_rpc"
    assert codex_app.runtime_review_transport == "app_server_review"
    assert codex_app.runtime_session_support["fork"]

    t3code = AgentIntegration.get("t3code")
    assert t3code.support_class == "attach_client"
    assert t3code.attach_command == "controlkeel attach codex-cli"
    assert t3code.runtime_transport == "t3code_provider_runtime"
    assert t3code.runtime_review_transport == "orchestration_domain_event"
    assert t3code.runtime_session_support["fork"]
    assert t3code.runtime_capabilities[:policy_gate] == true
    assert t3code.runtime_capabilities[:tool_approval] == true

    assert vllm.support_class == "provider_only"
    assert vllm.preferred_target == "provider-profile"
    assert vllm.attach_command == nil
    assert "vscode-companion" in vscode.export_targets
    assert vscode.phase_model == "review_only"
    assert vscode.runtime_transport == "vscode_companion"
    assert vscode.runtime_auth_owner == "workspace"
    assert vscode.runtime_review_transport == "vscode_ipc"
    assert vscode.auth_mode == "ck_owned"
    assert opencode.auth_mode == "agent_runtime"
    assert opencode.runtime_transport == "opencode_sdk"
    assert opencode.experience_profile.cost == "host_subscription_or_agent_metered"
    assert opencode.experience_profile.token_pressure == "host_quota_sensitive"
    assert copilot.auth_mode == "agent_runtime"
    assert copilot.runtime_transport == "hook_session_parser"
  end
end
