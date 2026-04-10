defmodule ControlKeel.Skills.SkillTarget do
  @moduledoc false

  alias ControlKeel.AgentAdapters.Registry, as: AdapterRegistry

  defstruct [
    :id,
    :label,
    :description,
    :native,
    :default_scope,
    :supported_scopes,
    :release_bundle
  ]

  def catalog do
    [
      target(
        "codex",
        "Codex",
        "Open-standard skills plus Codex companion agents and OpenAI metadata.",
        true,
        "user",
        ["user", "project", "export"],
        true
      ),
      target(
        "codex-plugin",
        "Codex plugin bundle",
        "Marketplace-ready Codex plugin bundle with skills, agents, hooks, MCP, and marketplace metadata.",
        true,
        "export",
        ["user", "project", "export"],
        true
      ),
      target(
        "claude-standalone",
        "Claude Code",
        "Standalone Claude skills and subagents in .claude directories.",
        true,
        "user",
        ["user", "project", "export"],
        false
      ),
      target(
        "claude-plugin",
        "Claude plugin bundle",
        "Marketplace-ready Claude Code plugin bundle with skills, agents, and MCP.",
        true,
        "export",
        ["export"],
        true
      ),
      target(
        "cline-native",
        "Cline native bundle",
        "Cline-native skills, `.clinerules` guidance, workflows, and MCP companion config.",
        true,
        "project",
        ["user", "project", "export"],
        true
      ),
      target(
        "cursor-native",
        "Cursor native bundle",
        "Cursor-native rules, project prompts, and MCP companion config.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "windsurf-native",
        "Windsurf native bundle",
        "Windsurf-native rules, project prompts, and MCP companion config.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "continue-native",
        "Continue native bundle",
        "Continue-native prompts, checks guidance, and MCP companion config.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "letta-code-native",
        "Letta Code native bundle",
        "Letta Code-native skills, checked-in hook settings, MCP registration helpers, and headless/remote guidance.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "pi-native",
        "Pi native bundle",
        "Pi-native command bundle, review extension manifest, MCP companion config, and browser review instructions.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "roo-native",
        "Roo Code native bundle",
        "Roo-native skills, `.roo` rules/commands/guidance, `.roomodes`, and MCP companion config.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "goose-native",
        "Goose native bundle",
        "Goose `.goosehints`, workflow recipe, extension config snippet, and MCP companion files.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "opencode-native",
        "OpenCode native bundle",
        "OpenCode-native plugins, agents, commands, MCP config, and governance instructions.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "gemini-cli-native",
        "Gemini CLI extension bundle",
        "Gemini CLI extension with manifest, MCP server, custom commands, agent skills, and GEMINI.md context.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "kiro-native",
        "Kiro native bundle",
        "Kiro Agent Hooks, steering files, MCP config, and governance instructions.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "kilo-native",
        "Kilo native bundle",
        "Kilo-native skills, slash-command workflows, MCP config, and AGENTS.md governance instructions.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "amp-native",
        "Amp native bundle",
        "Amp TypeScript plugin with event hooks, custom tools, commands, and governance instructions.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "augment-native",
        "Augment native bundle",
        "Augment workspace bundle with `.augment` skills, subagents, commands, rules, MCP config, and governance instructions.",
        true,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "augment-plugin",
        "Augment plugin bundle",
        "Local Auggie plugin bundle with hooks, agents, commands, rules, skills, and MCP bridge.",
        true,
        "export",
        ["export"],
        true
      ),
      target(
        "hermes-native",
        "Hermes Agent bundle",
        "Hermes-native skills, AGENTS context, and MCP companion config.",
        true,
        "user",
        ["user", "project", "export"],
        true
      ),
      target(
        "openclaw-native",
        "OpenClaw native bundle",
        "Workspace or managed OpenClaw skills plus MCP companion config.",
        true,
        "project",
        ["user", "project", "export"],
        true
      ),
      target(
        "openclaw-plugin",
        "OpenClaw plugin bundle",
        "Plugin-ready OpenClaw bundle with skills, manifest, and MCP companion config.",
        true,
        "export",
        ["export"],
        true
      ),
      target(
        "copilot-plugin",
        "Copilot / VS Code plugin bundle",
        "Plugin bundle for GitHub Copilot CLI and VS Code agent mode.",
        true,
        "export",
        ["export"],
        true
      ),
      target(
        "github-repo",
        "GitHub repo config",
        "Repository-level Copilot / VS Code skills, agents, and MCP config.",
        true,
        "project",
        ["project", "export"],
        false
      ),
      target(
        "droid-bundle",
        "Factory Droid bundle",
        "Factory Droid `.factory` skills, droids, commands, and MCP config.",
        true,
        "project",
        ["user", "project", "export"],
        true
      ),
      target(
        "droid-plugin",
        "Factory Droid plugin bundle",
        "Shareable Factory plugin bundle with plugin manifest, skills, commands, droids, hooks, and MCP config.",
        true,
        "export",
        ["export"],
        true
      ),
      target(
        "forge-acp",
        "Forge ACP bundle",
        "ACP companion bundle plus portable MCP fallback files for Forge.",
        true,
        "user",
        ["user", "project", "export"],
        true
      ),
      target(
        "open-standard",
        "Open-standard skills",
        "Portable AgentSkills bundle for any client that supports SKILL.md directories.",
        true,
        "project",
        ["user", "project", "export"],
        true
      ),
      target(
        "instructions-only",
        "Instructions only",
        "Companion AGENTS / CLAUDE / Copilot instruction snippets for MCP-only tools.",
        false,
        "project",
        ["project", "export"],
        true
      ),
      target(
        "open-swe-runtime",
        "Open SWE runtime export",
        "Headless runtime export with AGENTS context, webhook, and CI recipes for Open SWE.",
        false,
        "export",
        ["project", "export"],
        true
      ),
      target(
        "devin-runtime",
        "Devin runtime export",
        "Headless runtime export with AGENTS context, custom MCP recipe, and webhook guidance for Devin.",
        false,
        "export",
        ["project", "export"],
        true
      ),
      target(
        "cloudflare-workers-runtime",
        "Cloudflare Workers runtime export",
        "Governed Cloudflare Workers AI agent with D1, KV, R2, and MCP governance integration.",
        false,
        "export",
        ["project", "export"],
        true
      ),
      target(
        "executor-runtime",
        "Executor runtime export",
        "Typed integration-runtime export for OpenAPI, GraphQL, MCP, and custom JS functions through Executor.",
        false,
        "export",
        ["project", "export"],
        true
      ),
      target(
        "virtual-bash-runtime",
        "Virtual bash runtime export",
        "CK-owned virtual-workspace runtime export for just-bash-style discovery with governed shell fallback.",
        false,
        "export",
        ["project", "export"],
        true
      ),
      target(
        "framework-adapter",
        "Framework adapter template",
        "Adapter/export scaffold for framework-backed integrations such as DSPy, GEPA, and DeepAgents.",
        false,
        "export",
        ["export"],
        true
      ),
      target(
        "provider-profile",
        "Provider profile template",
        "Provider/model profile template for integrations such as Codestral.",
        false,
        "export",
        ["export"],
        true
      )
    ] ++ AdapterRegistry.skill_targets()
  end

  def ids, do: Enum.map(catalog(), & &1.id)

  def get(id), do: Enum.find(catalog(), &(&1.id == id))

  def release_targets do
    catalog()
    |> Enum.filter(& &1.release_bundle)
    |> Enum.map(& &1.id)
  end

  defp target(id, label, description, native, default_scope, supported_scopes, release_bundle) do
    %__MODULE__{
      id: id,
      label: label,
      description: description,
      native: native,
      default_scope: default_scope,
      supported_scopes: supported_scopes,
      release_bundle: release_bundle
    }
  end
end
