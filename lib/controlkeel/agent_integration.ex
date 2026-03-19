defmodule ControlKeel.AgentIntegration do
  @moduledoc false

  defstruct [
    :id,
    :label,
    :category,
    :description,
    :attach_command,
    :config_location,
    :companion_delivery,
    :preferred_target,
    :default_scope,
    export_targets: []
  ]

  def catalog do
    [
      integration(
        "claude-code",
        "Claude Code",
        "native-first",
        "Uses the official Claude CLI MCP registration flow and installs native Claude skills by default.",
        "controlkeel attach claude-code",
        "Claude CLI local MCP registration (`claude mcp add-json ... --scope local`).",
        "Installs `.claude/skills` and `.claude/agents`; can also export a publishable Claude plugin bundle.",
        "claude-standalone",
        "user",
        ["claude-standalone", "claude-plugin"]
      ),
      integration(
        "codex-cli",
        "Codex CLI",
        "native-first",
        "Writes MCP config and installs open-standard skills plus a Codex operator agent.",
        "controlkeel attach codex-cli",
        "Codex MCP config (`~/.codex/config.json` or project-scoped equivalent).",
        "Installs `.agents/skills` and `.codex/agents`; can also export a portable Codex bundle.",
        "codex",
        "user",
        ["codex", "open-standard"]
      ),
      integration(
        "vscode",
        "VS Code agent mode",
        "repo-native",
        "Prepares repository-native skill, agent, and MCP files for VS Code discovery.",
        "controlkeel attach vscode",
        "Repository MCP config in `.github/mcp.json` and `.vscode/mcp.json`.",
        "Writes `.github/skills`, `.github/agents`, and repo MCP config; can also export a Copilot / VS Code plugin bundle.",
        "github-repo",
        "project",
        ["github-repo", "copilot-plugin"]
      ),
      integration(
        "copilot",
        "GitHub Copilot",
        "repo-native",
        "Prepares repository-native Copilot skills, custom agent files, and MCP config.",
        "controlkeel attach copilot",
        "Repository MCP config in `.github/mcp.json` and `.vscode/mcp.json`.",
        "Writes `.github/skills`, `.github/agents`, and repo MCP config; can also export a Copilot / VS Code plugin bundle.",
        "github-repo",
        "project",
        ["github-repo", "copilot-plugin"]
      ),
      integration(
        "cursor",
        "Cursor",
        "mcp-plus-instructions",
        "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        "controlkeel attach cursor",
        "Cursor global MCP config file.",
        "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        "instructions-only",
        "project",
        ["instructions-only"]
      ),
      integration(
        "windsurf",
        "Windsurf",
        "mcp-plus-instructions",
        "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        "controlkeel attach windsurf",
        "Windsurf global MCP config file.",
        "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        "instructions-only",
        "project",
        ["instructions-only"]
      ),
      integration(
        "kiro",
        "Kiro",
        "mcp-plus-instructions",
        "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        "controlkeel attach kiro",
        "Kiro MCP config file.",
        "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        "instructions-only",
        "project",
        ["instructions-only"]
      ),
      integration(
        "amp",
        "Amp",
        "mcp-plus-instructions",
        "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        "controlkeel attach amp",
        "Amp MCP config file.",
        "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        "instructions-only",
        "project",
        ["instructions-only"]
      ),
      integration(
        "opencode",
        "OpenCode",
        "mcp-plus-instructions",
        "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        "controlkeel attach opencode",
        "OpenCode MCP config file.",
        "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        "instructions-only",
        "project",
        ["instructions-only"]
      ),
      integration(
        "gemini-cli",
        "Gemini CLI",
        "mcp-plus-instructions",
        "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        "controlkeel attach gemini-cli",
        "Gemini CLI MCP config file.",
        "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        "instructions-only",
        "project",
        ["instructions-only"]
      ),
      integration(
        "continue",
        "Continue",
        "mcp-plus-instructions",
        "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        "controlkeel attach continue",
        "Continue MCP config file.",
        "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        "instructions-only",
        "project",
        ["instructions-only"]
      ),
      integration(
        "aider",
        "Aider",
        "mcp-plus-instructions",
        "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        "controlkeel attach aider",
        "Aider MCP config file in the current project.",
        "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        "instructions-only",
        "project",
        ["instructions-only"]
      )
    ]
  end

  def ids, do: Enum.map(catalog(), & &1.id)

  def get(id), do: Enum.find(catalog(), &(&1.id == id))

  def label(id) do
    case get(id) do
      %__MODULE__{label: label} -> label
      nil -> id
    end
  end

  def categories do
    [
      {"native-first", "Native skills install during attach"},
      {"repo-native", "Repository-native files or plugin bundles"},
      {"mcp-plus-instructions", "MCP attach plus generated instruction snippets"}
    ]
  end

  defp integration(
         id,
         label,
         category,
         description,
         attach_command,
         config_location,
         companion_delivery,
         preferred_target,
         default_scope,
         export_targets
       ) do
    %__MODULE__{
      id: id,
      label: label,
      category: category,
      description: description,
      attach_command: attach_command,
      config_location: config_location,
      companion_delivery: companion_delivery,
      preferred_target: preferred_target,
      default_scope: default_scope,
      export_targets: export_targets
    }
  end
end
