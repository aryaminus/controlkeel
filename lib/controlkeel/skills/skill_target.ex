defmodule ControlKeel.Skills.SkillTarget do
  @moduledoc false

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
        "export",
        ["export"],
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
    ]
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
