defmodule ControlKeel.AgentIntegration do
  @moduledoc false

  alias ControlKeel.AgentAdapters.Registry, as: AdapterRegistry
  alias ControlKeel.AgentRuntimes.Registry, as: RuntimeRegistry
  alias ControlKeel.Distribution

  defstruct [
    :id,
    :label,
    :category,
    :support_class,
    :description,
    :attach_command,
    :runtime_export_command,
    :config_location,
    :companion_delivery,
    :install_experience,
    :review_experience,
    :submission_mode,
    :feedback_mode,
    :phase_model,
    :browser_embed,
    :subagent_visibility,
    :runtime_transport,
    :runtime_auth_owner,
    :runtime_review_transport,
    :confidence_level,
    :preferred_target,
    :default_scope,
    :router_agent_id,
    :auto_bootstrap,
    :provider_bridge,
    :upstream_slug,
    :upstream_docs_url,
    :auth_mode,
    :mcp_mode,
    :skills_mode,
    :alias_of,
    :registry_match,
    :registry_id,
    :registry_version,
    :registry_url,
    :registry_stale,
    :agent_uses_ck_via,
    :ck_runs_agent_via,
    :execution_support,
    :autonomy_mode,
    :experience_profile,
    plan_phase_support: [],
    artifact_surfaces: [],
    package_outputs: [],
    direct_install_methods: [],
    runtime_session_support: %{},
    runtime_capabilities: %{},
    supported_scopes: [],
    required_mcp_tools: [],
    install_channels: [],
    export_targets: []
  ]

  def catalog do
    [
      attach_client(%{
        id: "claude-code",
        label: "Claude Code",
        category: "native-first",
        description:
          "Uses the official Claude CLI MCP registration flow, installs native Claude skills by default, and can export a local plugin-dir bundle.",
        attach_command: "controlkeel attach claude-code",
        config_location:
          "Claude CLI local MCP registration (`claude mcp add-json ... --scope local`).",
        companion_delivery:
          "Installs `.claude/skills` and `.claude/agents`; can also export a local Claude plugin-dir bundle for direct host install.",
        preferred_target: "claude-standalone",
        default_scope: "user",
        router_agent_id: "claude-code",
        auth_mode: "env_bridge",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "anthropic/claude-code",
        upstream_docs_url: "https://docs.anthropic.com/en/docs/claude-code",
        provider_bridge: %{
          supported: true,
          provider: "anthropic",
          mode: "env_bridge",
          owner: "agent"
        },
        supported_scopes: ["user", "project"],
        export_targets: ["claude-standalone", "claude-plugin"]
      }),
      attach_client(%{
        id: "codex-cli",
        label: "Codex CLI",
        category: "native-first",
        description:
          "Writes MCP config, installs native Codex skills plus open-standard compatibility skills, adds Codex custom agents plus lifecycle hooks, and ships review, annotate, diff, completion, and last command aliases.",
        attach_command: "controlkeel attach codex-cli",
        config_location:
          "Codex MCP config (`~/.codex/config.toml` or `<project>/.codex/config.toml`).",
        companion_delivery:
          "Installs `.codex/skills`, `.agents/skills`, `.codex/config.toml`, `.codex/hooks.json`, `.codex/hooks`, `.codex/agents`, and `.codex/commands`; can also export portable Codex bundles or a Codex plugin.",
        preferred_target: "codex",
        default_scope: "user",
        router_agent_id: "codex-cli",
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "openai/codex",
        upstream_docs_url: "https://github.com/openai/codex",
        provider_bridge: %{
          supported: true,
          provider: "openai",
          mode: "agent_runtime",
          owner: "agent"
        },
        supported_scopes: ["user", "project"],
        submission_mode: "tool_call",
        feedback_mode: "tool_call",
        phase_model: "review_only",
        export_targets: ["codex", "codex-plugin", "open-standard"]
      }),
      attach_client(%{
        id: "vscode",
        label: "VS Code agent mode",
        category: "repo-native",
        description:
          "Prepares repository-native skill, agent, and MCP files for VS Code discovery and ships a packaged review companion extension.",
        attach_command: "controlkeel attach vscode",
        config_location: "Repository MCP config in `.github/mcp.json` and `.vscode/mcp.json`.",
        companion_delivery:
          "Writes `.github/skills`, `.github/agents`, and repo MCP config; can also export a VS Code companion `.vsix` and a Copilot / VS Code plugin bundle.",
        preferred_target: "github-repo",
        default_scope: "project",
        router_agent_id: nil,
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "microsoft/vscode",
        upstream_docs_url: "https://code.visualstudio.com/docs/copilot/chat/chat-agent-mode",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["github-repo", "copilot-plugin", "vscode-companion"]
      }),
      attach_client(%{
        id: "copilot",
        label: "GitHub Copilot",
        category: "repo-native",
        description:
          "Prepares repository-native Copilot skills, custom agent files, and MCP config.",
        attach_command: "controlkeel attach copilot",
        config_location: "Repository MCP config in `.github/mcp.json` and `.vscode/mcp.json`.",
        companion_delivery:
          "Writes `.github/skills`, `.github/agents`, and repo MCP config; can also export a Copilot / VS Code plugin bundle.",
        preferred_target: "github-repo",
        default_scope: "project",
        router_agent_id: "copilot",
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "github/copilot",
        upstream_docs_url: "https://docs.github.com/copilot",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["github-repo", "copilot-plugin"]
      }),
      attach_client(%{
        id: "pi",
        label: "Pi",
        category: "repo-native",
        description:
          "Prepares a Pi-native review extension bundle, MCP config, browser review command flow, and a publishable npm extension package.",
        attach_command: "controlkeel attach pi",
        config_location: "Repository Pi config under `.pi/` plus `pi-extension.json`.",
        companion_delivery:
          "Installs `.agents/skills`, `.pi/commands`, `.pi/mcp.json`, `pi-extension.json`, `PI.md`, and a publishable npm extension package for governed browser reviews.",
        preferred_target: "pi-native",
        default_scope: "project",
        router_agent_id: "pi",
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["pi-native", "instructions-only"],
        review_experience: "browser_review",
        submission_mode: "command",
        feedback_mode: "command_reply",
        artifact_surfaces: [
          ".agents/skills",
          ".pi/commands",
          ".pi/mcp.json",
          "pi-extension.json",
          "PI.md"
        ]
      }),
      attach_client(%{
        id: "cursor",
        label: "Cursor",
        category: "native-first",
        description:
          "Attaches the MCP server and prepares Cursor-native rules, review commands, background-agent guidance, MCP config, and portable skill bundles for governed repo work.",
        attach_command: "controlkeel attach cursor",
        config_location: "Cursor global MCP config file.",
        companion_delivery:
          "Installs `.agents/skills`, `.cursor/skills`, `.cursor/rules`, `.cursor/commands`, `.cursor/agents`, `.cursor/background-agents`, `.cursor/hooks.json` + `.cursor/hooks/`, `.cursor/mcp.json`, and a distributable `.cursor-plugin/` bundle (manifest, mirrored rules/skills/agents/commands, plugin `hooks/hooks.json`); can also export a portable native Cursor bundle.",
        preferred_target: "cursor-native",
        default_scope: "project",
        router_agent_id: "cursor",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "cursor",
        upstream_docs_url: "https://cursor.com",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["cursor-native", "instructions-only"]
      }),
      attach_client(%{
        id: "windsurf",
        label: "Windsurf",
        category: "native-first",
        description:
          "Attaches the MCP server and prepares Windsurf-native rules, review commands, workflows, hooks, MCP config, and portable skill bundles for governed repo work.",
        attach_command: "controlkeel attach windsurf",
        config_location: "Windsurf global MCP config file.",
        companion_delivery:
          "Installs `.agents/skills`, `.windsurf/rules`, `.windsurf/commands`, `.windsurf/workflows`, `.windsurf/hooks`, and `.windsurf/mcp.json`; can also export a portable native Windsurf bundle.",
        preferred_target: "windsurf-native",
        default_scope: "project",
        router_agent_id: "windsurf",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "windsurf",
        upstream_docs_url: "https://windsurf.com",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["windsurf-native", "instructions-only"]
      }),
      attach_client(%{
        id: "kiro",
        label: "Kiro",
        category: "native-first",
        description:
          "Attaches MCP server and delivers native governance via Kiro Agent Hooks, steering files, command guides, tool controls, and MCP config.",
        attach_command: "controlkeel attach kiro",
        config_location: "Kiro MCP config and `.kiro/hooks/`, `.kiro/steering/`.",
        companion_delivery:
          "Exports governance hooks, steering files, review commands, tool policy settings, MCP config, and `AGENTS.md` instructions.",
        preferred_target: "kiro-native",
        default_scope: "project",
        router_agent_id: "kiro",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "kiro",
        upstream_docs_url: "https://kiro.dev",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["kiro-native", "instructions-only"]
      }),
      attach_client(%{
        id: "kilo",
        label: "Kilo Code",
        category: "native-first",
        description:
          "Attaches MCP server and delivers native governance via Kilo Agent Skills, slash-command workflows, and AGENTS.md guidance.",
        attach_command: "controlkeel attach kilo",
        config_location:
          "Kilo MCP config lives in `kilo.json`, `./.kilo/kilo.json`, or `~/.config/kilo/kilo.json`; skills load from `.kilo/skills/` and workflows from `.kilo/commands/`.",
        companion_delivery:
          "Exports `.kilo/skills`, `.kilo/commands`, `.kilo/kilo.json`, and `AGENTS.md` for governed repo work.",
        preferred_target: "kilo-native",
        default_scope: "project",
        router_agent_id: "kilo",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "Kilo-Org/kilocode",
        upstream_docs_url: "https://kilo.ai/docs",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["kilo-native", "instructions-only"]
      }),
      attach_client(%{
        id: "amp",
        label: "Amp",
        category: "native-first",
        description:
          "Attaches MCP server and delivers native governance via Amp TypeScript plugins, a native skill bundle, custom tools, and commands.",
        attach_command: "controlkeel attach amp",
        config_location: "Amp MCP config and `.amp/plugins/`.",
        companion_delivery:
          "Exports a governance TypeScript plugin with `amp.on` hooks, `ck-validate` tool, a native `controlkeel-governance` skill bundle, review commands, package scaffold, and `AGENTS.md` instructions.",
        preferred_target: "amp-native",
        default_scope: "project",
        router_agent_id: "amp",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "sourcegraph/amp",
        upstream_docs_url: "https://ampcode.com",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["amp-native", "instructions-only"]
      }),
      attach_client(%{
        id: "augment",
        label: "Augment / Auggie CLI",
        category: "native-first",
        description:
          "Attaches MCP server and delivers native governance via Auggie workspace commands, subagents, rules, plugin hooks, and ACP-compatible runtime transport.",
        attach_command: "controlkeel attach augment",
        config_location:
          "Workspace assets under `.augment/`; persistent MCP and permission settings live in `~/.augment/settings.json` when configured outside a plugin.",
        companion_delivery:
          "Exports `.augment/skills`, `.augment/agents`, `.augment/commands`, `.augment/rules`, `.augment/mcp.json`, a settings snippet, and a local `.augment-plugin` bundle with hooks and MCP bridge.",
        preferred_target: "augment-native",
        default_scope: "project",
        router_agent_id: "augment",
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "augmentcode/auggie",
        upstream_docs_url: "https://docs.augmentcode.com/cli",
        provider_bridge: %{
          supported: true,
          provider: "augment",
          mode: "agent_runtime",
          owner: "agent"
        },
        supported_scopes: ["project", "export"],
        export_targets: ["augment-native", "augment-plugin", "instructions-only"]
      }),
      attach_client(%{
        id: "opencode",
        label: "OpenCode",
        category: "native-first",
        description:
          "Attaches MCP server and delivers native governance via OpenCode plugins, agents, commands, and instruction files.",
        attach_command: "controlkeel attach opencode",
        config_location:
          "OpenCode MCP config and `.opencode/plugins/`, `.opencode/agents/`, `.opencode/commands/`.",
        companion_delivery:
          "Exports a governance plugin, review agent profile, `/controlkeel-review` command set, MCP config, and a publishable npm plugin package.",
        preferred_target: "opencode-native",
        default_scope: "project",
        router_agent_id: "opencode",
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "sst/opencode",
        upstream_docs_url: "https://opencode.ai",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["opencode-native", "instructions-only"]
      }),
      attach_client(%{
        id: "gemini-cli",
        label: "Gemini CLI",
        category: "native-first",
        description:
          "Attaches MCP server and delivers native governance via Gemini CLI extensions with manifest, multiple custom commands, agent skills, and GEMINI.md context.",
        attach_command: "controlkeel attach gemini-cli",
        config_location:
          "Gemini CLI extension directory and `.gemini/commands/`, `skills/`, `GEMINI.md`.",
        companion_delivery:
          "Exports a `gemini-extension.json` manifest, submit-plan and review TOML commands, `controlkeel-governance` agent skill, extension README, and `GEMINI.md` instructions.",
        preferred_target: "gemini-cli-native",
        default_scope: "project",
        router_agent_id: "gemini-cli",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "google-gemini/gemini-cli",
        upstream_docs_url: "https://github.com/google-gemini/gemini-cli",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["gemini-cli-native", "instructions-only"]
      }),
      attach_client(%{
        id: "continue",
        label: "Continue",
        category: "native-first",
        description:
          "Attaches the MCP server and prepares Continue-native prompts, command prompts, headless review flows, and MCP config for governed repo work.",
        attach_command: "controlkeel attach continue",
        config_location: "Continue MCP config file.",
        companion_delivery:
          "Installs `.continue/prompts`, `.continue/commands`, and `.continue/mcpServers/controlkeel.yaml`; can also export a portable native Continue bundle.",
        preferred_target: "continue-native",
        default_scope: "project",
        router_agent_id: "continue",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "continuedev/continue",
        upstream_docs_url: "https://docs.continue.dev",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["continue-native", "instructions-only"]
      }),
      attach_client(%{
        id: "letta-code",
        label: "Letta Code",
        category: "native-first",
        description:
          "Prepares Letta Code skills, checked-in hook settings, MCP registration helpers, and remote/headless guidance for governed repo work.",
        attach_command: "controlkeel attach letta-code",
        config_location:
          "Letta project config lives in `.letta/settings.json` with optional local overrides in `.letta/settings.local.json`; MCP servers are added through Letta's `/mcp` flow and skills load from `.agents/skills`.",
        companion_delivery:
          "Installs `.agents/skills`, `.letta/settings.json`, `.letta/hooks`, `.letta/controlkeel-mcp.sh`, `.letta/README.md`, and portable `.mcp.json` guidance for Letta-native MCP, hooks, remote, and headless use.",
        preferred_target: "letta-code-native",
        default_scope: "project",
        router_agent_id: "letta-code",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "letta-ai/letta-code",
        upstream_docs_url: "https://docs.letta.com/letta-code/cli-reference",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["letta-code-native", "instructions-only"]
      }),
      attach_client(%{
        id: "aider",
        label: "Aider",
        category: "mcp-plus-instructions",
        description:
          "Attaches the MCP server and prepares command-driven Aider instructions, config, and review helpers for governed repo workflows.",
        attach_command: "controlkeel attach aider",
        config_location: "Aider MCP config file in the current project.",
        companion_delivery:
          "Installs `AIDER.md`, `.aider.conf.yml`, `.aider/commands`, and shared instruction snippets for command-driven review flows.",
        preferred_target: "instructions-only",
        default_scope: "project",
        router_agent_id: "aider",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "instructions_only",
        upstream_slug: "aider",
        upstream_docs_url: "https://aider.chat",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["instructions-only"]
      }),
      attach_client(%{
        id: "cline",
        label: "Cline",
        category: "native-first",
        description:
          "Registers ControlKeel as an MCP server for Cline and installs Cline-native skills, rules, commands, hooks, and workflow guidance.",
        attach_command: "controlkeel attach cline",
        config_location:
          "Cline CLI MCP settings live in `~/.cline/data/settings/cline_mcp_settings.json` or `<CLINE_DIR>/data/settings/cline_mcp_settings.json`; project rules live in `.clinerules/` and project skills in `.cline/skills/`.",
        companion_delivery:
          "Installs `.cline/skills`, `.cline/commands`, `.cline/hooks`, emits `.clinerules` guidance plus a workflow, and prepares a Cline MCP config snippet.",
        preferred_target: "cline-native",
        default_scope: "project",
        router_agent_id: "cline",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "cline/cline",
        upstream_docs_url: "https://docs.cline.bot/cline-cli/configuration",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["user", "project"],
        export_targets: ["cline-native"]
      }),
      attach_client(%{
        id: "roo-code",
        label: "Roo Code",
        category: "native-first",
        description:
          "Installs Roo-native skills, rules, commands, cloud-agent guidance, and `.roomodes` companion files for governed repo work.",
        attach_command: "controlkeel attach roo-code",
        config_location:
          "Roo project companions live in `.roo/skills`, `.roo/rules`, `.roo/commands`, `.roo/guidance`, and `.roomodes` at the repo root.",
        companion_delivery:
          "Installs `.roo/skills`, emits repo-native rules, submit-plan commands, cloud-agent guidance, and a ControlKeel `.roomodes` mode.",
        preferred_target: "roo-native",
        default_scope: "project",
        router_agent_id: "roo-code",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "RooCodeInc/Roo-Code",
        upstream_docs_url: "https://docs.roocode.com",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["roo-native"]
      }),
      attach_client(%{
        id: "goose",
        label: "Goose",
        category: "native-first",
        description:
          "Registers ControlKeel as a Goose MCP extension and installs project-native `.goosehints`, review commands, and workflow companions.",
        attach_command: "controlkeel attach goose",
        config_location:
          "Goose custom extensions live in `~/.config/goose/config.yaml`; project context lives in `.goosehints`, `AGENTS.md`, and optional `goose/workflow_recipes/` files.",
        companion_delivery:
          "Merges a ControlKeel Goose extension into the user Goose config and writes repo-local `.goosehints`, review commands, workflow recipes, and MCP companion files.",
        preferred_target: "goose-native",
        default_scope: "project",
        router_agent_id: "goose",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "block/goose",
        upstream_docs_url: "https://github.com/block/goose",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["goose-native"]
      }),
      attach_client(%{
        id: "hermes-agent",
        label: "Hermes Agent",
        category: "native-first",
        description:
          "Registers ControlKeel as an MCP server for Hermes and installs native Hermes-compatible skills.",
        attach_command: "controlkeel attach hermes-agent",
        config_location:
          "Hermes settings live under `~/.hermes/`; provider/model config is in `config.yaml`, keys in `.env`, and MCP servers use the Hermes MCP integration.",
        companion_delivery:
          "Installs `.hermes/skills`, emits `AGENTS.md` context, and generates Hermes MCP config snippets.",
        preferred_target: "hermes-native",
        default_scope: "user",
        router_agent_id: "hermes-agent",
        auth_mode: "config_reference",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "NousResearch/hermes-agent",
        upstream_docs_url: "https://hermes-agent.nousresearch.com/docs/",
        provider_bridge: %{
          supported: true,
          mode: "config_reference",
          owner: "agent",
          config_paths: ["~/.hermes/config.yaml", "~/.hermes/.env"]
        },
        supported_scopes: ["user", "project"],
        export_targets: ["hermes-native"]
      }),
      attach_client(%{
        id: "openclaw",
        label: "OpenClaw",
        category: "native-first",
        description:
          "Installs OpenClaw-compatible skills, emits plugin bundles, and writes MCP companion config through documented OpenClaw paths.",
        attach_command: "controlkeel attach openclaw",
        config_location:
          "Managed config lives in `~/.openclaw/openclaw.json`; model provider metadata is merged into per-agent `models.json` and skills live in `~/.openclaw/skills` or `<workspace>/skills`.",
        companion_delivery:
          "Installs workspace or managed skills, emits `openclaw.plugin.json`, and prepares MCP-ready bundle files.",
        preferred_target: "openclaw-native",
        default_scope: "project",
        router_agent_id: "openclaw",
        auth_mode: "config_reference",
        mcp_mode: "native",
        skills_mode: "plugin_bundle",
        upstream_slug: "openclaw",
        upstream_docs_url: "https://docs.openclaw.ai",
        provider_bridge: %{
          supported: true,
          mode: "config_reference",
          owner: "agent",
          config_paths: ["~/.openclaw/openclaw.json", "~/.openclaw/agents/*/models.json"]
        },
        supported_scopes: ["user", "project"],
        export_targets: ["openclaw-native", "openclaw-plugin"]
      }),
      attach_client(%{
        id: "droid",
        label: "Factory Droid",
        category: "native-first",
        description:
          "Generates repo-local `.factory` skills, droids, commands, and MCP config aligned with Droid's user/project hierarchy, and can also export a shareable Factory plugin bundle.",
        attach_command: "controlkeel attach droid",
        config_location:
          "Factory settings live in `~/.factory/settings.json` or `<repo>/.factory/settings.local.json`; MCP config is layered through `~/.factory/mcp.json` and `<repo>/.factory/mcp.json`.",
        companion_delivery:
          "Installs `.factory/skills`, `.factory/droids`, `.factory/commands`, and `.factory/mcp.json` bundles for user or project scope, and can export a `.factory-plugin` bundle for Droid's marketplace/plugin flow.",
        preferred_target: "droid-bundle",
        default_scope: "project",
        router_agent_id: "droid",
        auth_mode: "gateway_base_url",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "factory-ai/droid",
        upstream_docs_url: "https://docs.factory.ai/cli/configuration/settings",
        provider_bridge: %{
          supported: true,
          mode: "gateway_base_url",
          owner: "agent",
          config_paths: ["~/.factory/settings.json", "<repo>/.factory/settings.local.json"]
        },
        supported_scopes: ["user", "project"],
        export_targets: ["droid-bundle", "droid-plugin"]
      }),
      attach_client(%{
        id: "forge",
        label: "Forge",
        category: "native-first",
        description:
          "Exports ControlKeel as an ACP-aware companion bundle for Forge while preserving MCP fallback files.",
        attach_command: "controlkeel attach forge",
        config_location:
          "Forge is an ACP client; session/auth capabilities come from the Agent Client Protocol and Forge's agent runtime.",
        companion_delivery:
          "Generates an ACP session companion plus portable MCP fallback files under `controlkeel/dist/forge-acp`.",
        preferred_target: "forge-acp",
        default_scope: "user",
        router_agent_id: "forge",
        auth_mode: "acp_session",
        mcp_mode: "export_only",
        skills_mode: "instructions_only",
        upstream_slug: "forgeagents/forge",
        upstream_docs_url: "https://forgeagents.dev",
        provider_bridge: %{
          supported: true,
          mode: "acp_session",
          owner: "agent"
        },
        supported_scopes: ["user", "project"],
        export_targets: ["forge-acp", "instructions-only"]
      }),
      attach_client(%{
        id: "warp",
        label: "Warp",
        category: "native-first",
        description:
          "Attaches ControlKeel to Warp's local Oz agents by writing `.warp/skills`, open-standard compatibility skills, repo `AGENTS.md`, and a copy-pasteable MCP snippet for the Warp desktop app.",
        attach_command: "controlkeel attach warp",
        config_location:
          "Warp local MCP servers are configured in the desktop app or Warp Drive settings; project and user skills live in `.warp/skills` or `~/.warp/skills`.",
        companion_delivery:
          "Installs `.warp/skills`, `.agents/skills`, `.warp/controlkeel-mcp.json`, `.warp/README.md`, and repo `AGENTS.md` for project scope.",
        preferred_target: "warp-native",
        default_scope: "project",
        router_agent_id: "warp",
        auth_mode: "agent_runtime",
        mcp_mode: "config_reference",
        skills_mode: "native",
        upstream_slug: "warpdotdev/Warp",
        upstream_docs_url: "https://docs.warp.dev/agent-platform",
        provider_bridge: %{
          supported: true,
          provider: "warp",
          mode: "agent_runtime",
          owner: "agent"
        },
        supported_scopes: ["user", "project"],
        export_targets: ["warp-native"]
      }),
      headless_runtime(%{
        id: "warp-oz",
        label: "Warp Oz Cloud Agents",
        category: "headless-runtime",
        description:
          "Headless export for Oz cloud agents with repo `AGENTS.md`, cloud MCP config examples, schedule/integration guidance, and API/SDK run templates.",
        runtime_export_command: "controlkeel runtime export warp-oz",
        config_location:
          "Oz cloud agents run through the Oz CLI, Oz web app, schedules, integrations, or API/SDK with YAML/JSON agent config files and environment IDs.",
        companion_delivery:
          "Emits repo `AGENTS.md`, Oz runtime README, cloud agent config examples, and API request templates instead of a local attach target.",
        preferred_target: "warp-oz-runtime",
        default_scope: "project",
        auth_mode: "oauth_runtime",
        mcp_mode: "export_only",
        skills_mode: "instructions_only",
        upstream_slug: "warpdotdev/Warp",
        upstream_docs_url: "https://docs.warp.dev/agent-platform/cloud-agents/platform",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["warp-oz-runtime"]
      }),
      headless_runtime(%{
        id: "devin",
        label: "Devin (Cognition)",
        category: "headless-runtime",
        description:
          "Headless export for Devin's hosted coding runtime using repo `AGENTS.md`, a custom MCP server recipe, and webhook guidance.",
        runtime_export_command: "controlkeel runtime export devin",
        config_location:
          "Devin config lives in the Devin web app MCP marketplace and custom-MCP settings, not a local attach file.",
        companion_delivery:
          "Emits repo `AGENTS.md`, a Devin custom MCP config snippet, and webhook/runtime notes instead of a local attach target.",
        preferred_target: "devin-runtime",
        default_scope: "project",
        auth_mode: "oauth_runtime",
        mcp_mode: "export_only",
        skills_mode: "instructions_only",
        upstream_slug: "cognition/devin",
        upstream_docs_url: "https://docs.devin.ai/work-with-devin/mcp",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["devin-runtime"]
      }),
      attach_client(%{
        id: "devin-terminal",
        label: "Devin for Terminal",
        category: "native-first",
        description:
          "Attaches ControlKeel to Devin's local terminal agent by writing `.devin/` MCP, skills, hooks, and custom subagent files plus open-standard compatibility skills.",
        attach_command: "controlkeel attach devin-terminal",
        config_location:
          "Devin for Terminal config in `<project>/.devin/config.json` or `~/.config/devin/config.json`.",
        companion_delivery:
          "Installs `.devin/config.json`, `.devin/hooks.v1.json`, `.devin/hooks`, `.devin/skills`, `.devin/agents`, `.agents/skills`, and repo `AGENTS.md`.",
        preferred_target: "devin-terminal-native",
        default_scope: "project",
        router_agent_id: "devin-terminal",
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "cognition/devin",
        upstream_docs_url: "https://cli.devin.ai/docs",
        provider_bridge: %{
          supported: true,
          provider: "cognition",
          mode: "agent_runtime",
          owner: "agent"
        },
        supported_scopes: ["user", "project"],
        export_targets: ["devin-terminal-native"]
      }),
      headless_runtime(%{
        id: "open-swe",
        label: "Open SWE",
        category: "headless-runtime",
        description:
          "Headless export for LangChain's asynchronous coding runtime using repo `AGENTS.md`, webhook, and issue/PR integration guidance.",
        runtime_export_command: "controlkeel runtime export open-swe",
        config_location:
          "Open SWE runs through GitHub, Slack, Linear, or web triggers rather than a local MCP attach flow.",
        companion_delivery:
          "Emits repo `AGENTS.md`, CK webhook guidance, and CI/headless recipes instead of a local attach target.",
        preferred_target: "open-swe-runtime",
        default_scope: "project",
        auth_mode: "ck_owned",
        mcp_mode: "export_only",
        skills_mode: "instructions_only",
        upstream_slug: "langchain-ai/open-swe",
        upstream_docs_url: "https://github.com/langchain-ai/open-swe",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["open-swe-runtime"]
      }),
      attach_client(%{
        id: "multica",
        label: "Multica",
        category: "native-first",
        description:
          "Attaches ControlKeel to the Multica local daemon, which orchestrates Claude Code, Codex, OpenCode, Hermes, Kiro, and other coding agents as managed team members with issue-tracking, skills, and autopilots.",
        attach_command: "controlkeel attach multica",
        config_location:
          "Multica daemon config at `~/.multica/` with per-profile directories at `~/.multica/profiles/<name>/`. MCP servers are configured per-agent via the Multica web UI or CLI (`multica agent list`).",
        companion_delivery:
          "Installs `.agents/skills`, repo `AGENTS.md`, and a `.multica/controlkeel-mcp.json` snippet for importing into the Multica agent MCP settings. Daemon must already be running (`multica daemon start`).",
        preferred_target: "multica-native",
        default_scope: "project",
        router_agent_id: "multica",
        auth_mode: "agent_runtime",
        mcp_mode: "config_reference",
        skills_mode: "native",
        upstream_slug: "multica-ai/multica",
        upstream_docs_url: "https://github.com/multica-ai/multica",
        provider_bridge: %{
          supported: true,
          provider: "multica",
          mode: "agent_runtime",
          owner: "agent"
        },
        supported_scopes: ["user", "project"],
        export_targets: ["multica-native"]
      }),
      headless_runtime(%{
        id: "multica-cloud",
        label: "Multica Cloud",
        category: "headless-runtime",
        description:
          "Headless export for Multica Cloud-hosted agent workspaces, autopilots, and issue-triggered agent runs with repo `AGENTS.md` and MCP config guidance.",
        runtime_export_command: "controlkeel runtime export multica-cloud",
        config_location:
          "Multica Cloud agents are managed via the Multica web app and CLI. Autopilots (cron-triggered agent tasks) and issue assignments are configured through the Multica workspace settings.",
        companion_delivery:
          "Emits repo `AGENTS.md`, a Multica cloud MCP config snippet, autopilot guidance, and skills delivery notes instead of a local attach target.",
        preferred_target: "multica-cloud-runtime",
        default_scope: "project",
        auth_mode: "oauth_runtime",
        mcp_mode: "export_only",
        skills_mode: "instructions_only",
        upstream_slug: "multica-ai/multica",
        upstream_docs_url: "https://github.com/multica-ai/multica",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["multica-cloud-runtime"]
      }),
      headless_runtime(%{
        id: "executor",
        label: "Executor",
        category: "headless-runtime",
        description:
          "Typed integration runtime for OpenAPI, GraphQL, MCP, Google Discovery, and custom JS functions with auth/approval resume flows.",
        runtime_export_command: "controlkeel runtime export executor",
        config_location:
          "Executor runs as a hosted or local runtime/UI surface rather than a repo-local native attach target.",
        companion_delivery:
          "Emits repo `AGENTS.md`, an Executor runtime README, source/bootstrap snippets, and approval/webhook guidance instead of a local attach target.",
        preferred_target: "executor-runtime",
        default_scope: "project",
        auth_mode: "oauth_runtime",
        mcp_mode: "export_only",
        skills_mode: "instructions_only",
        upstream_slug: "RhysSullivan/executor",
        upstream_docs_url: "https://github.com/RhysSullivan/executor",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["executor-runtime"]
      }),
      headless_runtime(%{
        id: "virtual-bash",
        label: "Virtual Bash Runtime",
        category: "headless-runtime",
        description:
          "CK-owned virtual-workspace runtime for just-bash-style discovery, repo search, and governed shell fallback through configured sandbox adapters.",
        runtime_export_command: "controlkeel runtime export virtual-bash",
        config_location:
          "Runs as a repo-local or hosted outer loop around CK virtual-workspace MCP tools plus sandboxed shell execution, not a local attach target.",
        companion_delivery:
          "Emits repo `AGENTS.md`, a virtual-runtime README, a machine-readable runtime manifest, and shell bootstrap guidance instead of a host-specific attach file.",
        preferred_target: "virtual-bash-runtime",
        default_scope: "project",
        auth_mode: "ck_owned",
        mcp_mode: "export_only",
        skills_mode: "instructions_only",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["virtual-bash-runtime"]
      }),
      framework_adapter(%{
        id: "dspy",
        label: "DSPy",
        category: "framework-adapter",
        description:
          "Framework adapter for benchmark harnesses and policy-training exports, not a first-class local attach client.",
        companion_delivery:
          "Appears in benchmark/export surfaces and adapter templates rather than `attach`.",
        preferred_target: "framework-adapter",
        default_scope: "export",
        auth_mode: "ck_owned",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "stanfordnlp/dspy",
        upstream_docs_url: "https://github.com/stanfordnlp/dspy",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["export"],
        export_targets: ["framework-adapter"]
      }),
      framework_adapter(%{
        id: "gepa",
        label: "GEPA",
        category: "framework-adapter",
        description:
          "Optimizer/policy-training adapter surface for GEPA-style workflows, not a local attach target.",
        companion_delivery:
          "Appears in benchmark and policy-training adapter exports rather than `attach`.",
        preferred_target: "framework-adapter",
        default_scope: "export",
        auth_mode: "ck_owned",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "stanfordnlp/dspy",
        upstream_docs_url: "https://github.com/stanfordnlp/dspy",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["export"],
        export_targets: ["framework-adapter"]
      }),
      framework_adapter(%{
        id: "deepagents",
        label: "DeepAgents",
        category: "framework-adapter",
        description:
          "Runtime harness adapter for LangGraph DeepAgents and benchmark subject integration.",
        companion_delivery:
          "Appears in benchmark/export surfaces rather than a standalone `attach` flow.",
        preferred_target: "framework-adapter",
        default_scope: "export",
        auth_mode: "ck_owned",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "langchain-ai/deepagents",
        upstream_docs_url: "https://github.com/langchain-ai/deepagents",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["export"],
        export_targets: ["framework-adapter"]
      }),
      framework_adapter(%{
        id: "fastmcp",
        label: "FastMCP",
        category: "framework-adapter",
        description:
          "Framework/tooling surface for MCP client-server interop and sampling, not a local `attach` target.",
        companion_delivery:
          "Appears in runtime/export docs as a generic MCP interoperability path rather than a dedicated attach flow.",
        preferred_target: "framework-adapter",
        default_scope: "export",
        auth_mode: "none",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "jlowin/fastmcp",
        upstream_docs_url: "https://gofastmcp.com/clients/sampling",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        supported_scopes: ["export"],
        export_targets: ["framework-adapter"]
      }),
      framework_adapter(%{
        id: "conductor",
        label: "Conductor",
        category: "framework-adapter",
        description:
          "Desktop orchestration app that runs bundled Claude Code and Codex in isolated workspaces. Not a first-class `controlkeel attach` target, but it can consume the same repo-local Claude Code MCP, `CLAUDE.md`, and slash-command surfaces that CK already ships.",
        companion_delivery:
          "Use the Claude Code CK attach/install surfaces inside repositories opened by Conductor. The same `.mcp.json`, `CLAUDE.md`, and `.claude/commands` assets are what Conductor documents today.",
        preferred_target: "claude-standalone",
        default_scope: "project",
        auth_mode: "heuristic",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "conductor/build",
        upstream_docs_url: "https://docs.conductor.build/",
        provider_bridge: %{
          supported: true,
          provider: "anthropic",
          mode: "env_bridge",
          owner: "agent"
        },
        supported_scopes: ["user", "project"],
        export_targets: ["claude-standalone", "claude-plugin", "instructions-only"],
        agent_uses_ck_via: ["local_mcp", "native_skills", "commands"],
        artifact_surfaces: [".mcp.json", "CLAUDE.md", ".claude/commands"],
        review_experience: "browser_review",
        submission_mode: "command",
        feedback_mode: "command_reply",
        install_experience: "guided",
        confidence_level: "experimental",
        phase_model: "host_plan_mode",
        browser_embed: "external",
        subagent_visibility: "primary_only",
        execution_support: "inbound_only",
        ck_runs_agent_via: "none"
      }),
      framework_adapter(%{
        id: "paperclip",
        label: "Paperclip",
        category: "framework-adapter",
        description:
          "Multi-agent orchestration control plane that runs CK-enabled local agents through adapter configs and heartbeats, not through a native `controlkeel attach` path.",
        companion_delivery:
          "Use CK's native attach/install surfaces inside the underlying Paperclip agent runtimes such as Claude, Codex, Gemini, OpenClaw, Hermes, Pi, and Cursor. Paperclip itself is modeled as an orchestration adapter with its own config, plugin, and skills-manager layers.",
        preferred_target: "framework-adapter",
        default_scope: "project",
        auth_mode: "config_reference",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "paperclipai/paperclip",
        upstream_docs_url: "https://docs.paperclip.ing/adapters/overview",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        supported_scopes: ["project", "export"],
        export_targets: ["framework-adapter"],
        agent_uses_ck_via: ["local_mcp", "native_skills", "commands", "plugin"],
        artifact_surfaces: [
          "~/.paperclip/instances/default/config.json",
          "Paperclip adapter config",
          "Paperclip plugins",
          "AGENTS.md"
        ],
        install_experience: "guided",
        confidence_level: "experimental",
        execution_support: "inbound_only",
        ck_runs_agent_via: "none"
      }),
      framework_adapter(%{
        id: "dmux",
        label: "dmux",
        category: "framework-adapter",
        description:
          "Parallel-agent tmux/worktree orchestrator. CK support inside dmux-managed worktrees is real, but it comes from the underlying repo-local agent surfaces rather than a dedicated `controlkeel attach dmux` command.",
        companion_delivery:
          "Install dmux separately, then attach CK to the underlying agents you run inside dmux such as Codex, Claude Code, OpenCode, Copilot, or Gemini CLI. dmux worktrees inherit those repo-local CK surfaces, and `.dmux-hooks/` can enforce governed setup or pre-merge checks.",
        preferred_target: "framework-adapter",
        default_scope: "project",
        auth_mode: "config_reference",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "standardagents/dmux",
        upstream_docs_url: "https://github.com/standardagents/dmux",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        supported_scopes: ["project", "export"],
        export_targets: ["framework-adapter"],
        agent_uses_ck_via: ["local_mcp", "native_skills", "commands", "hooks"],
        artifact_surfaces: [
          ".dmux.defaults.json",
          ".dmux-hooks/",
          ".dmux/worktrees/",
          "underlying repo-local host config (.codex/, .claude/, .opencode/, .github/, .gemini/)",
          "AGENTS.md"
        ],
        direct_install_methods: [
          direct_install("npm_cli", "dmux via npm", "npm -g i dmux"),
          direct_install(
            "openrouter_env",
            "OpenRouter key",
            ~s|export OPENROUTER_API_KEY="sk-or-..."|
          ),
          direct_install("ck_attach_codex", "CK + Codex", "controlkeel attach codex-cli"),
          direct_install(
            "ck_attach_claude",
            "CK + Claude Code",
            "controlkeel attach claude-code"
          ),
          direct_install("ck_attach_opencode", "CK + OpenCode", "controlkeel attach opencode")
        ],
        install_experience: "guided",
        confidence_level: "experimental",
        review_experience: "browser_review",
        submission_mode: "command",
        feedback_mode: "command_reply",
        phase_model: "host_plan_mode",
        browser_embed: "external",
        subagent_visibility: "all",
        execution_support: "inbound_only",
        ck_runs_agent_via: "none"
      }),
      framework_adapter(%{
        id: "augment-intent",
        label: "Intent by Augment",
        category: "framework-adapter",
        description:
          "Spec-driven, multi-agent orchestration workspace. Tracked as an orchestration adapter, not a CK attach target.",
        companion_delivery:
          "Appears in orchestration/export guidance while canonical CK execution still runs through shipped attach/runtime integrations.",
        preferred_target: "framework-adapter",
        default_scope: "export",
        auth_mode: "none",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "augmentcode/intent",
        upstream_docs_url: "https://docs.augmentcode.com/intent/overview",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        supported_scopes: ["export"],
        export_targets: ["framework-adapter"]
      }),
      provider_only(%{
        id: "codestral",
        label: "Codestral",
        category: "provider-only",
        description:
          "Provider/model profile template for Mistral Codestral-style APIs and proxy compatibility, not an attachable client.",
        companion_delivery:
          "Appears as a provider profile template and proxy-compatible model path.",
        preferred_target: "provider-profile",
        default_scope: "export",
        auth_mode: "ck_owned",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "mistral/codestral",
        upstream_docs_url: "https://docs.mistral.ai/capabilities/code_generation/",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["export"],
        export_targets: ["provider-profile"]
      }),
      provider_only(%{
        id: "ollama-runtime",
        label: "Ollama",
        category: "provider-only",
        description:
          "Local runtime profile for Ollama's native API and OpenAI-compatible bridge, not an attachable client.",
        companion_delivery: "Appears as a provider profile template and local-runtime guidance.",
        preferred_target: "provider-profile",
        default_scope: "export",
        auth_mode: "local",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "ollama/ollama",
        upstream_docs_url: "https://docs.ollama.com/api/openai-compatibility",
        provider_bridge: %{supported: false, mode: "local", owner: "local"},
        supported_scopes: ["export"],
        export_targets: ["provider-profile"]
      }),
      provider_only(%{
        id: "vllm",
        label: "vLLM",
        category: "provider-only",
        description:
          "OpenAI-compatible backend profile for vLLM deployments, configured through CK provider base URL and model settings.",
        companion_delivery:
          "Appears as a provider profile template for CK-owned OpenAI-compatible endpoints.",
        preferred_target: "provider-profile",
        default_scope: "export",
        auth_mode: "ck_owned",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "vllm-project/vllm",
        upstream_docs_url: "https://docs.vllm.ai/en/latest/serving/openai_compatible_server/",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["export"],
        export_targets: ["provider-profile"]
      }),
      provider_only(%{
        id: "sglang",
        label: "SGLang",
        category: "provider-only",
        description:
          "OpenAI-compatible backend profile for SGLang deployments, configured through CK provider base URL and model settings.",
        companion_delivery:
          "Appears as a provider profile template for CK-owned OpenAI-compatible endpoints.",
        preferred_target: "provider-profile",
        default_scope: "export",
        auth_mode: "ck_owned",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "sgl-project/sglang",
        upstream_docs_url: "https://docs.sglang.ai",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["export"],
        export_targets: ["provider-profile"]
      }),
      provider_only(%{
        id: "lmstudio",
        label: "LM Studio",
        category: "provider-only",
        description:
          "OpenAI-compatible backend profile for LM Studio local server endpoints, configured through CK provider base URL and model settings.",
        companion_delivery:
          "Appears as a provider profile template for CK-owned local OpenAI-compatible endpoints.",
        preferred_target: "provider-profile",
        default_scope: "export",
        auth_mode: "ck_owned",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "lmstudio/lmstudio",
        upstream_docs_url: "https://lmstudio.ai/docs/app/api/endpoints/openai",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["export"],
        export_targets: ["provider-profile"]
      }),
      provider_only(%{
        id: "huggingface",
        label: "Hugging Face Inference Providers",
        category: "provider-only",
        description:
          "OpenAI-compatible backend profile for Hugging Face chat-completion endpoints, configured through CK provider base URL and HF token settings.",
        companion_delivery:
          "Appears as a provider profile template for CK-owned Hugging Face endpoints.",
        preferred_target: "provider-profile",
        default_scope: "export",
        auth_mode: "ck_owned",
        mcp_mode: "none",
        skills_mode: "none",
        upstream_slug: "huggingface/inference-providers",
        upstream_docs_url:
          "https://huggingface.co/docs/inference-providers/tasks/chat-completion",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["export"],
        export_targets: ["provider-profile"]
      }),
      alias_entry(%{
        id: "claude-dispatch",
        label: "Claude Dispatch",
        category: "alias",
        description:
          "Alias to the shipped Claude Code integration until a separate native surface exists.",
        alias_of: "claude-code",
        auth_mode: "env_bridge",
        upstream_slug: "anthropic/claude-code",
        upstream_docs_url: "https://docs.anthropic.com/en/docs/claude-code",
        supported_scopes: ["user", "project"],
        preferred_target: "claude-standalone",
        export_targets: ["claude-standalone", "claude-plugin"]
      }),
      alias_entry(%{
        id: "cognition",
        label: "Cognition / Devin",
        category: "alias",
        description: "Alias to the shipped Devin headless-runtime export.",
        alias_of: "devin",
        auth_mode: "oauth_runtime",
        mcp_mode: "export_only",
        skills_mode: "instructions_only",
        upstream_slug: "cognition/devin",
        upstream_docs_url: "https://docs.devin.ai/work-with-devin/mcp",
        supported_scopes: ["project", "export"],
        preferred_target: "devin-runtime",
        export_targets: ["devin-runtime"]
      }),
      alias_entry(%{
        id: "cursor-agent",
        label: "Cursor agent",
        category: "alias",
        description: "Alias to the shipped Cursor integration.",
        alias_of: "cursor",
        auth_mode: "ck_owned",
        upstream_slug: "cursor",
        upstream_docs_url: "https://cursor.com",
        supported_scopes: ["project"],
        preferred_target: "cursor-native",
        export_targets: ["cursor-native", "instructions-only"]
      }),
      alias_entry(%{
        id: "codex",
        label: "Codex",
        category: "alias",
        description:
          "Alias to the shipped Codex CLI integration for ecosystems that label the terminal agent simply as Codex.",
        alias_of: "codex-cli",
        auth_mode: "agent_runtime",
        upstream_slug: "openai/codex",
        upstream_docs_url: "https://openai.com/codex",
        supported_scopes: ["user", "project"],
        preferred_target: "codex",
        export_targets: ["codex", "codex-plugin", "open-standard"]
      }),
      attach_client(%{
        id: "codex-app-server",
        label: "Codex app / app server surface",
        category: "native-first",
        description:
          "Uses the Codex app-server / shared config surface for governed runtime control, while reusing the same repo-local Codex MCP, hooks, skills, commands, and custom agents as the CLI integration.",
        attach_command: "controlkeel attach codex-cli",
        config_location:
          "Codex app-server shares Codex local config (`~/.codex/config.toml` or `<project>/.codex/config.toml`).",
        companion_delivery:
          "Installs `.codex/skills`, `.agents/skills`, `.codex/config.toml`, `.codex/hooks.json`, `.codex/hooks`, `.codex/agents`, and `.codex/commands`; use the Codex app-server protocol on top of that local surface.",
        preferred_target: "codex",
        default_scope: "user",
        router_agent_id: "codex-app-server",
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "openai/codex",
        upstream_docs_url: "https://github.com/openai/codex",
        provider_bridge: %{
          supported: true,
          provider: "openai",
          mode: "agent_runtime",
          owner: "agent"
        },
        supported_scopes: ["user", "project"],
        export_targets: ["codex", "codex-plugin", "open-standard"]
      }),
      alias_entry(%{
        id: "copilot-cli",
        label: "Copilot CLI",
        category: "alias",
        description:
          "Alias to the repo-native GitHub Copilot path; the `copilot-plugin` bundle covers CLI and VS Code agent mode.",
        alias_of: "copilot",
        auth_mode: "ck_owned",
        upstream_slug: "github/copilot",
        upstream_docs_url: "https://docs.github.com/copilot",
        supported_scopes: ["project"],
        preferred_target: "github-repo",
        export_targets: ["github-repo", "copilot-plugin"]
      }),
      alias_entry(%{
        id: "copilot-web",
        label: "GitHub Copilot web surfaces",
        category: "alias",
        description:
          "Alias for GitHub Copilot web and agent-management surfaces; CK support resolves to the canonical repo-native Copilot integration.",
        alias_of: "copilot",
        auth_mode: "ck_owned",
        upstream_slug: "github/copilot-web",
        upstream_docs_url: "https://docs.github.com/en/copilot",
        supported_scopes: ["project"],
        preferred_target: "github-repo",
        export_targets: ["github-repo", "copilot-plugin"]
      }),
      alias_entry(%{
        id: "augment-cli",
        label: "Augment CLI",
        category: "alias",
        description:
          "Alias to the shipped Augment / Auggie CLI integration and plugin bundle surfaces.",
        alias_of: "augment",
        auth_mode: "agent_runtime",
        upstream_slug: "augmentcode/auggie",
        upstream_docs_url: "https://docs.augmentcode.com/cli",
        supported_scopes: ["project", "export"],
        preferred_target: "augment-native",
        export_targets: ["augment-native", "augment-plugin", "instructions-only"]
      }),
      alias_entry(%{
        id: "auggie-cli",
        label: "Auggie CLI",
        category: "alias",
        description:
          "Alias to the shipped Augment / Auggie CLI integration and plugin bundle surfaces.",
        alias_of: "augment",
        auth_mode: "agent_runtime",
        upstream_slug: "augmentcode/auggie",
        upstream_docs_url: "https://docs.augmentcode.com/cli",
        supported_scopes: ["project", "export"],
        preferred_target: "augment-native",
        export_targets: ["augment-native", "augment-plugin", "instructions-only"]
      }),
      alias_entry(%{
        id: "cursor-web",
        label: "Cursor web/mobile surfaces",
        category: "alias",
        description:
          "Alias for Cursor web/mobile agent surfaces; CK support resolves to the canonical Cursor integration.",
        alias_of: "cursor",
        auth_mode: "ck_owned",
        upstream_slug: "cursor/web",
        upstream_docs_url: "https://cursor.com/blog/agent-web",
        supported_scopes: ["project"],
        preferred_target: "cursor-native",
        export_targets: ["cursor-native", "instructions-only"]
      }),
      alias_entry(%{
        id: "conductor-web",
        label: "Conductor web",
        category: "alias",
        description:
          "Alias for the Conductor app/web surface. CK resolves this to the Conductor compatibility row rather than a direct attach target.",
        alias_of: "conductor",
        auth_mode: "heuristic",
        upstream_slug: "conductor/build-web",
        upstream_docs_url: "https://docs.conductor.build/",
        supported_scopes: ["user", "project"],
        preferred_target: "claude-standalone",
        export_targets: ["claude-standalone", "claude-plugin", "instructions-only"]
      }),
      alias_entry(%{
        id: "gemini",
        label: "Gemini",
        category: "alias",
        description:
          "Alias to the shipped Gemini CLI integration for skill ecosystems that label the agent surface as Gemini.",
        alias_of: "gemini-cli",
        auth_mode: "ck_owned",
        upstream_slug: "google-gemini/gemini-cli",
        upstream_docs_url: "https://github.com/google-gemini/gemini-cli",
        supported_scopes: ["project", "export"],
        preferred_target: "gemini-cli-native",
        export_targets: ["gemini-cli-native", "instructions-only"]
      }),
      alias_entry(%{
        id: "kiro-cli",
        label: "Kiro CLI",
        category: "alias",
        description:
          "Alias to the shipped Kiro integration for ecosystems that distinguish the CLI name from the broader Kiro product.",
        alias_of: "kiro",
        auth_mode: "ck_owned",
        upstream_slug: "kiro",
        upstream_docs_url: "https://kiro.dev/cli",
        supported_scopes: ["project", "export"],
        preferred_target: "kiro-native",
        export_targets: ["kiro-native", "instructions-only"]
      }),
      alias_entry(%{
        id: "kimi-cli",
        label: "Kimi Code CLI",
        category: "alias",
        description:
          "Alias path for Kimi Code CLI through CK's canonical terminal-agent companion flow until a dedicated native CK target is validated.",
        alias_of: "codex-cli",
        auth_mode: "agent_runtime",
        upstream_slug: "MoonshotAI/kimi-cli",
        upstream_docs_url:
          "https://www.kimi.com/code/docs/en/kimi-cli/guides/getting-started.html",
        supported_scopes: ["user", "project"],
        preferred_target: "codex",
        export_targets: ["codex", "codex-plugin", "open-standard"]
      }),
      alias_entry(%{
        id: "roo",
        label: "Roo",
        category: "alias",
        description:
          "Alias to the shipped Roo Code integration for ecosystems that shorten the product name to Roo.",
        alias_of: "roo-code",
        auth_mode: "ck_owned",
        upstream_slug: "RooCodeInc/Roo-Code",
        upstream_docs_url: "https://roocode.com/",
        supported_scopes: ["project"],
        preferred_target: "roo-native",
        export_targets: ["roo-native", "instructions-only"]
      }),
      attach_client(%{
        id: "t3code",
        label: "T3 Chat / T3 Code",
        category: "native-first",
        description:
          "Treats T3 Code as a first-class Codex app-server runtime surface while reusing the same governed local `.codex/*` install path as Codex CLI.",
        attach_command: "controlkeel attach codex-cli",
        config_location:
          "T3 Code consumes the Codex local config surface (`~/.codex/config.toml` or `<project>/.codex/config.toml`).",
        companion_delivery:
          "Installs `.codex/skills`, `.agents/skills`, `.codex/config.toml`, `.codex/hooks.json`, `.codex/hooks`, `.codex/agents`, and `.codex/commands`; T3 Code uses that governed surface through its provider-neutral orchestration runtime.",
        preferred_target: "codex",
        default_scope: "user",
        router_agent_id: "t3code",
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "pingdotgg/t3code",
        upstream_docs_url: "https://github.com/pingdotgg/t3code",
        provider_bridge: %{supported: true, mode: "agent_runtime", owner: "agent"},
        supported_scopes: ["user", "project"],
        export_targets: ["codex", "codex-plugin", "open-standard"]
      }),
      unverified_entry(%{
        id: "jcode",
        label: "jcode",
        category: "research-compatible",
        description:
          "jcode is a distinct coding-agent harness with its own runtime and config model. CK can currently meet it through repo-local instructions and MCP wiring, but does not yet ship a native `attach jcode` installer/export path.",
        auth_mode: "none",
        upstream_slug: "1jehuang/jcode",
        upstream_docs_url: "https://github.com/1jehuang/jcode",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "native",
        skills_mode: "instructions_only",
        preferred_target: "instructions-only",
        export_targets: ["instructions-only"],
        agent_uses_ck_via: ["local_mcp"],
        artifact_surfaces: ["AGENTS.md", ".jcode/mcp.json", ".jcode/prompt-overlay.md"],
        direct_install_methods: [
          %{
            "kind" => "upstream_install",
            "label" => "Install jcode upstream",
            "command" =>
              "curl -fsSL https://raw.githubusercontent.com/1jehuang/jcode/master/scripts/install.sh | bash",
            "availability" => "research"
          },
          %{
            "kind" => "local_mcp",
            "label" => "Point jcode at local CK MCP",
            "command" =>
              ~s|Add {"servers":{"controlkeel":{"command":"controlkeel","args":["mcp","--project-root","/abs/path"]}}} to .jcode/mcp.json|,
            "availability" => "research"
          }
        ]
      }),
      unverified_entry(%{
        id: "antigravity",
        label: "Antigravity",
        category: "skills-compatible",
        description:
          "No verified native CK attach/runtime contract yet. ControlKeel support for Antigravity is currently through open-standard AgentSkills installs such as the skills.sh flow.",
        auth_mode: "none",
        upstream_slug: "unverified/antigravity",
        upstream_docs_url: "https://antigravity.google/",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "native",
        preferred_target: "open-standard",
        export_targets: ["open-standard"],
        agent_uses_ck_via: ["native_skills"],
        direct_install_methods: [
          %{
            "kind" => "skills_sh",
            "label" => "skills.sh install",
            "command" =>
              "npx skills add https://github.com/aryaminus/controlkeel --skill controlkeel-governance",
            "availability" => "supported"
          }
        ]
      }),
      unverified_entry(%{
        id: "clawdbot",
        label: "ClawdBot",
        category: "skills-compatible",
        description:
          "No verified native CK attach/runtime contract yet. ControlKeel support for ClawdBot is currently through open-standard AgentSkills installs such as the skills.sh flow.",
        auth_mode: "none",
        upstream_slug: "unverified/clawdbot",
        upstream_docs_url: "https://clawd.bot/",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "native",
        preferred_target: "open-standard",
        export_targets: ["open-standard"],
        agent_uses_ck_via: ["native_skills"],
        direct_install_methods: [
          %{
            "kind" => "skills_sh",
            "label" => "skills.sh install",
            "command" =>
              "npx skills add https://github.com/aryaminus/controlkeel --skill controlkeel-governance",
            "availability" => "supported"
          }
        ]
      }),
      unverified_entry(%{
        id: "nous-research",
        label: "Nous Research",
        category: "skills-compatible",
        description:
          "No verified generic CK attach/runtime contract exists for the broader Nous Research brand surface. CK's verified Nous path remains `hermes-agent`; broader compatibility is currently through open-standard AgentSkills installs such as the skills.sh flow.",
        auth_mode: "none",
        upstream_slug: "unverified/nous-research",
        upstream_docs_url: "https://nousresearch.com/",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "native",
        preferred_target: "open-standard",
        export_targets: ["open-standard"],
        agent_uses_ck_via: ["native_skills"],
        direct_install_methods: [
          %{
            "kind" => "skills_sh",
            "label" => "skills.sh install",
            "command" =>
              "npx skills add https://github.com/aryaminus/controlkeel --skill controlkeel-governance",
            "availability" => "supported"
          }
        ]
      }),
      unverified_entry(%{
        id: "rlm-agent",
        label: "RLM agent",
        category: "unverified",
        description:
          "Research name only. No canonical official upstream or documented ControlKeel integration contract was verified.",
        auth_mode: "none",
        upstream_slug: "unverified/rlm-agent",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "none"
      }),
      unverified_entry(%{
        id: "slate",
        label: "Slate",
        category: "unverified",
        description:
          "Research name only. No canonical official upstream or documented ControlKeel integration contract was verified.",
        auth_mode: "none",
        upstream_slug: "unverified/slate",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "none"
      }),
      unverified_entry(%{
        id: "retune",
        label: "Retune",
        category: "unverified",
        description:
          "Research name only. No canonical official upstream or documented ControlKeel integration contract was verified.",
        auth_mode: "none",
        upstream_slug: "khadgi-sujan/retune",
        upstream_docs_url: "https://github.com/khadgi-sujan/retune",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "none"
      }),
      unverified_entry(%{
        id: "claw-code",
        label: "Claw Code community ports",
        category: "unverified",
        description:
          "Community ports and rewrites tied to leaked Claude Code snapshots are tracked for awareness only. No stable, official integration contract has been verified for CK attach/runtime flows.",
        auth_mode: "none",
        upstream_slug: "instructkr/claw-code",
        upstream_docs_url: "https://github.com/instructkr/claw-code",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "none"
      }),
      unverified_entry(%{
        id: "claude-code-source-mirror",
        label: "Claude Code source mirror ports",
        category: "unverified",
        description:
          "Leak-derived Claude Code source mirrors/ports are intentionally classified as unverified. Prefer the official `claude-code` integration path and avoid treating mirror repos as trusted supply-chain inputs.",
        auth_mode: "none",
        upstream_slug: "VineeTagarwaL-code/claude-code",
        upstream_docs_url: "https://github.com/VineeTagarwaL-code/claude-code",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "none"
      }),
      unverified_entry(%{
        id: "trae",
        label: "Trae",
        category: "skills-compatible",
        description:
          "No verified native CK attach/runtime contract yet. ControlKeel support for Trae is currently through open-standard AgentSkills installs such as the skills.sh flow.",
        auth_mode: "none",
        upstream_slug: "unverified/trae",
        upstream_docs_url: "https://www.trae.ai/",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "native",
        preferred_target: "open-standard",
        export_targets: ["open-standard"],
        agent_uses_ck_via: ["native_skills"],
        direct_install_methods: [
          %{
            "kind" => "skills_sh",
            "label" => "skills.sh install",
            "command" =>
              "npx skills add https://github.com/aryaminus/controlkeel --skill controlkeel-governance",
            "availability" => "supported"
          }
        ]
      }),
      unverified_entry(%{
        id: "z-ai-cli",
        label: "Z.AI CLI ecosystem",
        category: "unverified",
        description:
          "Z.AI coding-agent CLI surfaces are evolving across official docs and community implementations; no single stable CK integration contract is verified yet.",
        auth_mode: "none",
        upstream_slug: "z-ai/cli-ecosystem",
        upstream_docs_url: "https://docs.z.ai/devpack/using5.1",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "none"
      }),
      unverified_entry(%{
        id: "capydotai",
        label: "Capy.ai / captain-agent style surfaces",
        category: "unverified",
        description:
          "Community references to capy/captain agent orchestration are tracked for awareness only; no canonical integration contract was verified.",
        auth_mode: "none",
        upstream_slug: "unverified/capydotai",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "none"
      }),
      unverified_entry(%{
        id: "neosigma",
        label: "NeoSigma",
        category: "unverified",
        description:
          "Tracked as an emerging agentic platform/research surface without a verified attach/runtime integration contract for ControlKeel yet.",
        auth_mode: "none",
        upstream_slug: "neosigma/agent-platform",
        upstream_docs_url: "https://www.neosigma.ai",
        provider_bridge: %{supported: false, mode: "none", owner: "none"},
        mcp_mode: "none",
        skills_mode: "none"
      }),
      framework_adapter(%{
        id: "open-agents",
        label: "Open Agents (Vercel)",
        category: "framework-adapter",
        description:
          "Cloud coding agent platform by Vercel Labs built on AI SDK, durable workflows, and sandboxed VMs. CK integrates via `.agents/skills/` discovery and CLI commands run through the agent's bash tool.",
        companion_delivery:
          "Drop `controlkeel-governance` skill into `.agents/skills/` for automatic discovery. Agent uses bash to run CK CLI. For fork-level integration, spread CK MCP tools into the agent's tool set via AI SDK.",
        preferred_target: "open-standard",
        default_scope: "project",
        auth_mode: "heuristic",
        mcp_mode: "hosted_optional",
        skills_mode: "native",
        upstream_slug: "vercel-labs/open-agents",
        upstream_docs_url: "https://github.com/vercel-labs/open-agents",
        provider_bridge: %{supported: true, mode: "byom", owner: "agent"},
        supported_scopes: ["project", "export"],
        export_targets: ["open-standard", "instructions-only"],
        dist_bundle: "controlkeel/dist/open-agents-runtime",
        install_experience: "guided",
        confidence_level: "experimental",
        phase_model: "host_plan_mode",
        browser_embed: "none",
        subagent_visibility: "all",
        execution_support: "inbound_only",
        ck_runs_agent_via: "none"
      }),
      headless_runtime(%{
        id: "cloudflare-workers",
        label: "Cloudflare Workers Agent",
        category: "headless-runtime",
        description:
          "Governed Cloudflare Workers Agent with D1, R2, Workers AI, and MCP governance tools.",
        runtime_export_command: "controlkeel runtime export cloudflare-workers",
        config_location:
          "Deploy as Cloudflare Worker with D1 database and R2 bucket for stateful agent execution.",
        companion_delivery:
          "Generates complete Worker project with CK governance integration, MCP tools, and deployment config.",
        preferred_target: "cloudflare-workers-runtime",
        default_scope: "project",
        auth_mode: "ck_owned",
        mcp_mode: "export_only",
        skills_mode: "instructions_only",
        upstream_slug: "cloudflare/workers-sdk",
        upstream_docs_url: "https://developers.cloudflare.com/agents/",
        provider_bridge: %{supported: true, mode: "byom", owner: "user"},
        supported_scopes: ["project", "export"],
        export_targets: ["cloudflare-workers-runtime"]
      })
    ]
  end

  def ids, do: Enum.map(catalog(), & &1.id)

  def attach_catalog do
    Enum.filter(catalog(), &attachable?/1)
  end

  def attachable_ids, do: Enum.map(attach_catalog(), & &1.id)

  def runtime_export_catalog do
    Enum.filter(catalog(), &(&1.support_class == "headless_runtime"))
  end

  def runtime_export_ids, do: Enum.map(runtime_export_catalog(), & &1.id)

  def get(id) do
    id = normalize_id(id)
    Enum.find(catalog(), &(&1.id == id))
  end

  def canonical(id) do
    case get(id) do
      %__MODULE__{alias_of: alias_of} when is_binary(alias_of) -> get(alias_of)
      integration -> integration
    end
  end

  def label(id) do
    case get(id) do
      %__MODULE__{label: label} -> label
      nil -> id
    end
  end

  def support_classes do
    [
      {"attach_client", "Attachable client with a real ControlKeel setup command"},
      {"headless_runtime", "Headless runtime export rather than a local attach target"},
      {"framework_adapter", "Framework adapter surfaced through benchmark/policy tooling"},
      {"provider_only", "Provider/model template surfaced through CK provider flows"},
      {"alias", "Alias that resolves to a canonical shipped target"},
      {"unverified", "Research name without a verified official integration contract"}
    ]
  end

  def categories do
    support_classes()
  end

  def execution_classes do
    [
      {"direct",
       "ControlKeel can launch the agent through a documented or configured local command."},
      {"handoff",
       "ControlKeel prepares a governed run package and waits for the agent or operator to continue."},
      {"runtime",
       "ControlKeel hands work to a remote or hosted runtime rather than a local CLI."},
      {"inbound_only",
       "The agent can use ControlKeel, but ControlKeel does not claim an outbound run surface."}
    ]
  end

  def install_channels(id \\ nil)

  def install_channels(nil), do: Distribution.install_channels()

  def install_channels(id) do
    case get(id) do
      %__MODULE__{install_channels: ids} -> Distribution.install_channels(ids)
      nil -> []
    end
  end

  def attachable?(%__MODULE__{support_class: "attach_client"}), do: true
  def attachable?(_integration), do: false

  def runtime_exportable?(%__MODULE__{support_class: "headless_runtime"}), do: true
  def runtime_exportable?(_integration), do: false

  def auth_owner(%__MODULE__{provider_bridge: %{supported: true, owner: owner}})
      when is_binary(owner),
      do: owner

  def auth_owner(%__MODULE__{auth_mode: "ck_owned"}), do: "controlkeel"
  def auth_owner(%__MODULE__{auth_mode: "agent_runtime"}), do: "agent"
  def auth_owner(%__MODULE__{auth_mode: "local"}), do: "local"
  def auth_owner(%__MODULE__{auth_mode: "none"}), do: "none"
  def auth_owner(%__MODULE__{auth_mode: "heuristic"}), do: "none"
  def auth_owner(%__MODULE__{}), do: "agent"

  defp attach_client(attrs) do
    entry(
      attrs
      |> Map.put(:support_class, "attach_client")
      |> Map.put_new(:auto_bootstrap, true)
    )
  end

  defp headless_runtime(attrs) do
    entry(
      attrs
      |> Map.put(:support_class, "headless_runtime")
      |> Map.put(:auto_bootstrap, false)
    )
  end

  defp framework_adapter(attrs) do
    entry(
      attrs
      |> Map.put(:support_class, "framework_adapter")
      |> Map.put(:auto_bootstrap, false)
    )
  end

  defp provider_only(attrs) do
    entry(
      attrs
      |> Map.put(:support_class, "provider_only")
      |> Map.put(:auto_bootstrap, false)
    )
  end

  defp alias_entry(attrs) do
    entry(
      attrs
      |> Map.put(:support_class, "alias")
      |> Map.put(:auto_bootstrap, false)
      |> Map.put_new(:mcp_mode, "native")
      |> Map.put_new(:skills_mode, "native")
      |> Map.put_new(:provider_bridge, %{supported: false, mode: "none", owner: "none"})
      |> Map.put(:companion_delivery, "Use the canonical target named in `alias_of`.")
    )
  end

  defp unverified_entry(attrs) do
    entry(
      attrs
      |> Map.put(:support_class, "unverified")
      |> Map.put(:auto_bootstrap, false)
      |> Map.put(
        :companion_delivery,
        "No shipped attach path. Treat as research-only until a documented upstream contract exists."
      )
      |> Map.put_new(:supported_scopes, [])
      |> Map.put_new(:export_targets, [])
    )
  end

  defp entry(attrs) do
    install_channels =
      attrs
      |> Map.get(:install_channels, Distribution.install_channels())
      |> Enum.map(fn
        %{id: id} -> id
        id -> id
      end)

    %__MODULE__{
      id: attrs.id,
      label: attrs.label,
      category: attrs.category,
      support_class: attrs.support_class,
      description: attrs.description,
      attach_command: attrs[:attach_command],
      runtime_export_command: attrs[:runtime_export_command],
      config_location: attrs[:config_location],
      companion_delivery: attrs[:companion_delivery],
      install_experience: attrs[:install_experience] || default_install_experience(attrs),
      review_experience: attrs[:review_experience] || default_review_experience(attrs),
      submission_mode: attrs[:submission_mode] || default_submission_mode(attrs),
      feedback_mode: attrs[:feedback_mode] || default_feedback_mode(attrs),
      confidence_level: attrs[:confidence_level] || default_confidence_level(attrs),
      preferred_target: attrs[:preferred_target],
      default_scope: attrs[:default_scope],
      router_agent_id: attrs[:router_agent_id],
      auto_bootstrap: attrs[:auto_bootstrap],
      provider_bridge:
        attrs[:provider_bridge] || %{supported: false, mode: "none", owner: "none"},
      upstream_slug: attrs[:upstream_slug],
      upstream_docs_url: attrs[:upstream_docs_url],
      auth_mode: attrs[:auth_mode] || "ck_owned",
      mcp_mode: attrs[:mcp_mode] || "none",
      skills_mode: attrs[:skills_mode] || "none",
      alias_of: attrs[:alias_of],
      agent_uses_ck_via: attrs[:agent_uses_ck_via] || default_agent_uses_ck_via(attrs),
      ck_runs_agent_via: attrs[:ck_runs_agent_via] || default_ck_runs_agent_via(attrs),
      execution_support: attrs[:execution_support] || default_execution_support(attrs),
      autonomy_mode: attrs[:autonomy_mode] || "policy_gated",
      experience_profile: attrs[:experience_profile] || default_experience_profile(attrs),
      plan_phase_support: attrs[:plan_phase_support] || default_plan_phase_support(attrs),
      artifact_surfaces: attrs[:artifact_surfaces] || default_artifact_surfaces(attrs),
      phase_model: attrs[:phase_model] || default_phase_model(attrs),
      browser_embed: attrs[:browser_embed] || default_browser_embed(attrs),
      subagent_visibility: attrs[:subagent_visibility] || default_subagent_visibility(attrs),
      package_outputs: attrs[:package_outputs] || default_package_outputs(attrs),
      direct_install_methods:
        attrs[:direct_install_methods] || default_direct_install_methods(attrs),
      supported_scopes: attrs[:supported_scopes] || [],
      required_mcp_tools:
        if(attrs[:support_class] in ["framework_adapter", "provider_only", "unverified"],
          do: [],
          else: Distribution.required_mcp_tools()
        ),
      install_channels: install_channels,
      export_targets: attrs[:export_targets] || []
    }
    |> AdapterRegistry.enrich_integration()
    |> RuntimeRegistry.enrich_integration()
  end

  defp default_experience_profile(attrs) do
    support_class = attrs[:support_class]
    execution_support = default_execution_support(attrs)
    auth_owner = auth_owner_for_attrs(attrs)

    %{
      cost: default_cost_profile(attrs, auth_owner),
      performance: default_performance_profile(support_class, execution_support),
      token_pressure: default_token_pressure_profile(attrs, auth_owner),
      time: default_time_profile(support_class, execution_support),
      ux: default_ux_profile(attrs, support_class)
    }
  end

  defp default_cost_profile(%{id: id}, _auth_owner) when id in ["ollama-runtime"] do
    "local_free"
  end

  defp default_cost_profile(%{support_class: "unverified"}, _auth_owner), do: "unknown"

  defp default_cost_profile(%{support_class: "provider_only"}, _auth_owner),
    do: "provider_metered"

  defp default_cost_profile(_attrs, "agent"), do: "host_subscription_or_agent_metered"
  defp default_cost_profile(_attrs, "controlkeel"), do: "ck_budget_metered"
  defp default_cost_profile(_attrs, "workspace"), do: "workspace_subscription"
  defp default_cost_profile(_attrs, _auth_owner), do: "unknown"

  defp default_performance_profile("headless_runtime", _execution_support),
    do: "background_runtime"

  defp default_performance_profile("provider_only", _execution_support), do: "provider_backend"

  defp default_performance_profile("framework_adapter", _execution_support),
    do: "adapter_dependent"

  defp default_performance_profile("unverified", _execution_support), do: "unknown"
  defp default_performance_profile(_support_class, "direct"), do: "interactive_direct"
  defp default_performance_profile(_support_class, "handoff"), do: "human_handoff"
  defp default_performance_profile(_support_class, "runtime"), do: "background_runtime"
  defp default_performance_profile(_support_class, _execution_support), do: "manual"

  defp default_token_pressure_profile(attrs, auth_owner) do
    cond do
      attrs[:support_class] in ["unverified", "framework_adapter"] -> "unknown"
      attrs[:support_class] == "provider_only" -> "provider_context_window"
      auth_owner == "agent" -> "host_quota_sensitive"
      auth_owner == "workspace" -> "workspace_quota_sensitive"
      true -> "ck_budget_sensitive"
    end
  end

  defp default_time_profile("headless_runtime", _execution_support), do: "long_running_ok"
  defp default_time_profile("unverified", _execution_support), do: "manual_research"
  defp default_time_profile(_support_class, "direct"), do: "fast_feedback"
  defp default_time_profile(_support_class, "handoff"), do: "checkpoint_driven"
  defp default_time_profile(_support_class, "runtime"), do: "long_running_ok"
  defp default_time_profile(_support_class, _execution_support), do: "manual"

  defp default_ux_profile(_attrs, "unverified"), do: "research_only"
  defp default_ux_profile(_attrs, "provider_only"), do: "provider_configuration"
  defp default_ux_profile(_attrs, "headless_runtime"), do: "runtime_export"

  defp default_ux_profile(attrs, _support_class) do
    case default_review_experience(attrs) do
      "native_review" -> "native_governed"
      "browser_review" -> "browser_review"
      "feedback_only" -> "guided_feedback"
      _ -> "manual"
    end
  end

  defp auth_owner_for_attrs(attrs) do
    case attrs[:auth_mode] do
      "agent_runtime" ->
        "agent"

      "env_bridge" ->
        "agent"

      "ck_owned" ->
        "controlkeel"

      "local" ->
        "controlkeel"

      _ ->
        attrs
        |> Map.get(:provider_bridge, %{owner: nil})
        |> case do
          %{owner: owner} when is_binary(owner) -> owner
          %{"owner" => owner} when is_binary(owner) -> owner
          _ -> "unknown"
        end
    end
  end

  defp default_agent_uses_ck_via(attrs) do
    case attrs[:id] do
      id when id in ["claude-code", "claude-dispatch"] ->
        ["local_mcp", "plugin", "native_skills"]

      id when id in ["codex-cli", "codex-app-server", "t3code"] ->
        ["local_mcp", "plugin", "native_skills"]

      id when id in ["vscode", "copilot", "copilot-cli"] ->
        ["local_mcp", "plugin", "native_skills", "workflows", "hooks", "commands"]

      id when id in ["cursor", "cursor-agent"] ->
        ["local_mcp", "native_skills", "rules", "commands", "workflows", "hooks", "plugin"]

      "windsurf" ->
        ["local_mcp", "native_skills", "rules", "commands", "workflows", "hooks"]

      id when id in ["cline", "continue", "roo-code"] ->
        ["local_mcp", "native_skills", "rules", "workflows", "commands"]

      "letta-code" ->
        ["local_mcp", "native_skills", "hooks"]

      "goose" ->
        ["local_mcp", "workflows", "hooks", "commands"]

      id when id in ["hermes-agent", "openclaw"] ->
        ["local_mcp", "plugin", "native_skills"]

      "droid" ->
        ["local_mcp", "native_skills", "commands", "plugin"]

      "kiro" ->
        ["local_mcp", "native_skills", "hooks", "rules", "commands"]

      "amp" ->
        ["local_mcp", "plugin", "native_skills", "commands", "tool_call"]

      "augment" ->
        ["local_mcp", "plugin", "native_skills", "rules", "commands", "hooks"]

      "devin-terminal" ->
        ["local_mcp", "native_skills", "rules", "hooks"]

      "warp" ->
        ["local_mcp", "native_skills", "rules"]

      "aider" ->
        ["local_mcp", "commands"]

      "opencode" ->
        ["local_mcp", "plugin", "native_skills", "rules", "commands"]

      "gemini-cli" ->
        ["local_mcp", "native_skills", "rules", "commands"]

      "pi" ->
        ["local_mcp", "native_skills", "commands", "rules"]

      id when id in ["forge", "devin", "open-swe"] ->
        ["hosted_mcp", "a2a"]

      "warp-oz" ->
        ["hosted_mcp", "native_skills", "rules"]

      "open-agents" ->
        ["native_skills", "cli_bash"]

      _ ->
        fallback_agent_uses_ck_via(attrs)
    end
  end

  defp fallback_agent_uses_ck_via(%{support_class: "attach_client"}), do: ["local_mcp"]
  defp fallback_agent_uses_ck_via(%{support_class: "headless_runtime"}), do: ["hosted_mcp"]
  defp fallback_agent_uses_ck_via(_attrs), do: []

  defp default_execution_support(attrs) do
    case attrs[:id] do
      id
      when id in [
             "claude-code",
             "claude-dispatch",
             "codex-cli",
             "codex-app-server",
             "t3code",
             "copilot",
             "copilot-cli",
             "cline",
             "continue",
             "devin-terminal",
             "warp",
             "letta-code",
             "aider",
             "augment",
             "opencode",
             "gemini-cli"
           ] ->
        "direct"

      id
      when id in [
             "cursor",
             "cursor-agent",
             "windsurf",
             "vscode",
             "roo-code",
             "goose",
             "kiro",
             "amp",
             "pi",
             "hermes-agent",
             "openclaw",
             "droid"
           ] ->
        "handoff"

      id when id in ["devin", "open-swe", "forge", "cognition"] ->
        "runtime"

      id when id in ["framework-adapter", "provider-profile"] ->
        "inbound_only"

      _ ->
        case attrs[:support_class] do
          "attach_client" -> "inbound_only"
          "headless_runtime" -> "runtime"
          _ -> "inbound_only"
        end
    end
  end

  defp default_ck_runs_agent_via(attrs) do
    case default_execution_support(attrs) do
      "direct" -> "embedded"
      "handoff" -> "handoff"
      "runtime" -> "runtime"
      _ -> "none"
    end
  end

  defp default_install_experience(%{support_class: support_class})
       when support_class in ["unverified", "alias"] do
    "fallback"
  end

  defp default_install_experience(%{support_class: support_class})
       when support_class in ["framework_adapter", "provider_only"] do
    "guided"
  end

  defp default_install_experience(_attrs), do: "first_class"

  defp default_review_experience(%{support_class: "unverified"}), do: "none"
  defp default_review_experience(%{support_class: "provider_only"}), do: "none"
  defp default_review_experience(%{support_class: "framework_adapter"}), do: "feedback_only"

  defp default_review_experience(%{id: id})
       when id in [
              "claude-code",
              "opencode",
              "windsurf",
              "cline",
              "kiro",
              "amp",
              "augment",
              "devin-terminal",
              "warp",
              "letta-code"
            ] do
    "native_review"
  end

  defp default_review_experience(%{support_class: "attach_client"}), do: "browser_review"
  defp default_review_experience(%{support_class: "headless_runtime"}), do: "browser_review"
  defp default_review_experience(_attrs), do: "feedback_only"

  defp default_submission_mode(%{support_class: "unverified"}), do: "manual"
  defp default_submission_mode(%{support_class: "provider_only"}), do: "manual"
  defp default_submission_mode(%{support_class: "framework_adapter"}), do: "manual"

  defp default_submission_mode(%{id: id})
       when id in ["claude-code", "amp", "opencode", "devin-terminal", "warp"] do
    "tool_call"
  end

  defp default_submission_mode(%{id: id})
       when id in ["vscode", "copilot", "windsurf", "cline", "kiro", "augment", "letta-code"] do
    "hook"
  end

  defp default_submission_mode(%{id: id})
       when id in ["cursor", "continue", "roo-code", "goose", "gemini-cli", "pi", "aider"] do
    "command"
  end

  defp default_submission_mode(%{id: "t3code"}), do: "tool_call"

  defp default_submission_mode(%{support_class: "headless_runtime"}), do: "file_watch"
  defp default_submission_mode(_attrs), do: "manual"

  defp default_feedback_mode(%{support_class: "unverified"}), do: "manual"
  defp default_feedback_mode(%{support_class: "provider_only"}), do: "manual"

  defp default_feedback_mode(%{id: id})
       when id in ["claude-code", "codex-cli", "amp", "opencode", "devin-terminal", "warp"] do
    "tool_call"
  end

  defp default_feedback_mode(%{id: "t3code"}), do: "tool_call"

  defp default_feedback_mode(%{id: id})
       when id in [
              "vscode",
              "copilot",
              "cursor",
              "windsurf",
              "continue",
              "cline",
              "letta-code",
              "goose",
              "kiro",
              "augment",
              "gemini-cli",
              "roo-code",
              "aider"
            ] do
    "command_reply"
  end

  defp default_feedback_mode(_attrs), do: "command_reply"

  defp default_plan_phase_support(%{support_class: support_class})
       when support_class in ["unverified", "provider_only"] do
    []
  end

  defp default_plan_phase_support(%{support_class: "framework_adapter"}),
    do: ["planning", "review"]

  defp default_plan_phase_support(_attrs), do: ["planning", "review", "execution"]

  defp default_confidence_level(%{support_class: "unverified"}), do: "research"
  defp default_confidence_level(%{support_class: "framework_adapter"}), do: "experimental"
  defp default_confidence_level(%{support_class: "provider_only"}), do: "experimental"
  defp default_confidence_level(_attrs), do: "shipped"

  defp default_phase_model(%{support_class: "unverified"}), do: "review_only"
  defp default_phase_model(%{support_class: "provider_only"}), do: "review_only"
  defp default_phase_model(%{support_class: "framework_adapter"}), do: "review_only"
  defp default_phase_model(%{id: "pi"}), do: "file_plan_mode"
  defp default_phase_model(%{id: "codex-cli"}), do: "review_only"
  defp default_phase_model(%{id: "t3code"}), do: "review_only"
  defp default_phase_model(%{id: "vscode"}), do: "review_only"

  defp default_phase_model(%{id: id}) when id in ["goose", "gemini-cli", "roo-code", "aider"],
    do: "review_only"

  defp default_phase_model(%{support_class: "attach_client"}), do: "host_plan_mode"
  defp default_phase_model(_attrs), do: "review_only"

  defp default_browser_embed(%{id: "vscode"}), do: "vscode_webview"
  defp default_browser_embed(%{support_class: "attach_client"}), do: "external"
  defp default_browser_embed(_attrs), do: "none"

  defp default_subagent_visibility(%{id: id})
       when id in ["claude-code", "copilot", "opencode", "codex-cli", "t3code", "pi"] do
    "primary_only"
  end

  defp default_subagent_visibility(%{id: "vscode"}), do: "none"
  defp default_subagent_visibility(%{support_class: "attach_client"}), do: "all"
  defp default_subagent_visibility(_attrs), do: "none"

  defp default_package_outputs(%{id: id}), do: AdapterRegistry.package_outputs(id)

  defp default_direct_install_methods(%{id: "claude-code"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach claude-code"),
      direct_install("local_plugin", "Claude plugin", "controlkeel plugin install claude"),
      direct_install(
        "local_plugin_dir",
        "Claude plugin dir",
        "claude --plugin-dir ./controlkeel/dist/claude-plugin"
      )
    ]
  end

  defp default_direct_install_methods(%{id: "codex-cli"}) do
    [
      direct_install("npm_cli", "Codex via npm", "npm install -g @openai/codex"),
      direct_install("brew_cli", "Codex via Homebrew", "brew install --cask codex"),
      direct_install("ck_attach", "CK attach", "controlkeel attach codex-cli"),
      direct_install("local_plugin", "Codex plugin", "controlkeel plugin install codex")
    ]
  end

  defp default_direct_install_methods(%{id: "t3code"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach codex-cli"),
      direct_install(
        "runtime_docs",
        "T3 Code runtime docs",
        "https://github.com/pingdotgg/t3code"
      )
    ]
  end

  defp default_direct_install_methods(%{id: "copilot"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach copilot"),
      direct_install("local_plugin", "Copilot plugin", "controlkeel plugin install copilot")
    ]
  end

  defp default_direct_install_methods(%{id: "opencode"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach opencode"),
      direct_install(
        "npm_plugin",
        "OpenCode npm plugin",
        ~s|"plugin": ["@aryaminus/controlkeel-opencode"]|
      )
    ]
  end

  defp default_direct_install_methods(%{id: "devin-terminal"}) do
    [
      direct_install(
        "host_cli",
        "Install Devin for Terminal",
        "curl -fsSL https://cli.devin.ai/install.sh | bash"
      ),
      direct_install("ck_attach", "CK attach", "controlkeel attach devin-terminal")
    ]
  end

  defp default_direct_install_methods(%{id: "warp"}) do
    [
      direct_install("host_app", "Install Warp", "brew install --cask warp"),
      direct_install("ck_attach", "CK attach", "controlkeel attach warp")
    ]
  end

  defp default_direct_install_methods(%{id: "warp-oz"}) do
    [
      direct_install(
        "host_cli",
        "Install Oz CLI",
        "brew tap warpdotdev/warp && brew update && brew install --cask oz"
      ),
      direct_install("ck_export", "CK runtime export", "controlkeel runtime export warp-oz")
    ]
  end

  defp default_direct_install_methods(%{id: "pi"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach pi"),
      direct_install(
        "npm_extension",
        "Pi npm extension",
        "pi install npm:@aryaminus/controlkeel-pi-extension"
      ),
      direct_install(
        "npm_extension_short",
        "Pi extension flag",
        "pi -e npm:@aryaminus/controlkeel-pi-extension"
      )
    ]
  end

  defp default_direct_install_methods(%{id: "vscode"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach vscode"),
      direct_install(
        "vsix",
        "VS Code VSIX",
        "code --install-extension controlkeel-vscode-companion.vsix"
      )
    ]
  end

  defp default_direct_install_methods(%{id: "gemini-cli"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach gemini-cli"),
      direct_install(
        "extension_link",
        "Gemini extension link",
        "gemini extensions link ./controlkeel/dist/gemini-cli-native"
      )
    ]
  end

  defp default_direct_install_methods(%{id: "kilo"}) do
    [direct_install("ck_attach", "CK attach", "controlkeel attach kilo")]
  end

  defp default_direct_install_methods(%{id: "amp"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach amp"),
      direct_install(
        "local_skill",
        "Amp skill",
        "amp skill add ./controlkeel/dist/amp-native/.agents/skills/controlkeel-governance"
      )
    ]
  end

  defp default_direct_install_methods(%{id: "augment"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach augment"),
      direct_install("host_cli", "Install Auggie CLI", "npm install -g @augmentcode/auggie"),
      direct_install(
        "local_plugin_dir",
        "Augment plugin dir",
        "auggie --plugin-dir ./controlkeel/dist/augment-plugin"
      )
    ]
  end

  defp default_direct_install_methods(%{id: "letta-code"}) do
    [
      direct_install("npm_cli", "Letta Code via npm", "npm install -g @letta-ai/letta-code"),
      direct_install("ck_attach", "CK attach", "controlkeel attach letta-code")
    ]
  end

  defp default_direct_install_methods(%{id: "openclaw"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach openclaw"),
      direct_install("local_plugin", "OpenClaw plugin", "controlkeel plugin install openclaw")
    ]
  end

  defp default_direct_install_methods(%{id: id})
       when id in [
              "cursor",
              "windsurf",
              "continue",
              "cline",
              "goose",
              "kiro",
              "augment",
              "roo-code",
              "aider",
              "hermes-agent",
              "droid",
              "forge",
              "devin-terminal"
            ] do
    [direct_install("ck_attach", "CK attach", "controlkeel attach #{id}")]
  end

  defp default_direct_install_methods(%{support_class: "headless_runtime"}), do: []
  defp default_direct_install_methods(%{support_class: "framework_adapter"}), do: []
  defp default_direct_install_methods(%{support_class: "provider_only"}), do: []
  defp default_direct_install_methods(%{support_class: "alias"}), do: []
  defp default_direct_install_methods(_attrs), do: []

  defp direct_install(kind, label, command) do
    %{
      "kind" => kind,
      "label" => label,
      "command" => command,
      "availability" => "shipped"
    }
  end

  defp default_artifact_surfaces(%{id: "claude-code"}),
    do: [".claude/skills", ".claude/agents", "Claude MCP registration"]

  defp default_artifact_surfaces(%{id: "codex-cli"}),
    do: [
      ".agents/skills",
      ".codex/skills",
      ".codex/config.toml",
      ".codex/hooks.json",
      ".codex/hooks",
      ".codex/agents",
      ".codex/commands"
    ]

  defp default_artifact_surfaces(%{id: "codex-app-server"}),
    do: default_artifact_surfaces(%{id: "codex-cli"})

  defp default_artifact_surfaces(%{id: "t3code"}),
    do: default_artifact_surfaces(%{id: "codex-cli"})

  defp default_artifact_surfaces(%{id: id}) when id in ["vscode", "copilot"] do
    [
      ".github/skills",
      ".github/agents",
      ".github/commands",
      ".github/mcp.json",
      ".github/copilot-instructions.md",
      ".vscode/mcp.json",
      ".vscode/extensions.json"
    ]
  end

  defp default_artifact_surfaces(%{id: "cursor"}),
    do: [
      ".agents/skills",
      ".cursor/skills",
      ".cursor/rules/controlkeel.mdc",
      ".cursor/commands",
      ".cursor/agents",
      ".cursor/background-agents",
      ".cursor/hooks.json",
      ".cursor/hooks",
      ".cursor/mcp.json",
      ".cursor-plugin/plugin.json",
      ".cursor-plugin/hooks/hooks.json",
      ".cursor-plugin/hooks",
      ".cursor-plugin/rules",
      ".cursor-plugin/skills",
      ".cursor-plugin/agents",
      ".cursor-plugin/commands",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "windsurf"}),
    do: [
      ".agents/skills",
      ".windsurf/rules/controlkeel.md",
      ".windsurf/commands",
      ".windsurf/workflows",
      ".windsurf/hooks.json",
      ".windsurf/hooks",
      ".windsurf/mcp.json",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "continue"}),
    do: [
      ".continue/skills",
      ".continue/prompts",
      ".continue/commands",
      ".continue/mcpServers/controlkeel.yaml",
      ".continue/mcp.json",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "letta-code"}),
    do: [
      ".agents/skills",
      ".letta/settings.json",
      ".letta/hooks",
      ".letta/controlkeel-mcp.sh",
      ".letta/README.md",
      ".mcp.json",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "cline"}),
    do: [
      ".cline/skills",
      ".clinerules",
      ".cline/commands",
      ".cline/hooks",
      ".cline/data/settings/cline_mcp_settings.json",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "goose"}),
    do: [
      ".goosehints",
      "goose/workflow_recipes/controlkeel-review.yaml",
      "goose/commands",
      "goose/controlkeel-extension.yaml",
      ".mcp.json"
    ]

  defp default_artifact_surfaces(%{id: "opencode"}),
    do: [".opencode/plugins", ".opencode/commands", ".opencode/mcp.json", "AGENTS.md"]

  defp default_artifact_surfaces(%{id: "devin-terminal"}),
    do: [
      ".agents/skills",
      ".devin/config.json",
      ".devin/hooks.v1.json",
      ".devin/hooks",
      ".devin/skills",
      ".devin/agents",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "warp"}),
    do: [
      ".warp/skills",
      ".agents/skills",
      ".warp/controlkeel-mcp.json",
      ".warp/README.md",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "warp-oz"}),
    do: [
      "warp-oz/controlkeel-agent-config.json",
      "warp-oz/controlkeel-api-request.json",
      "warp-oz/README.md",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "gemini-cli"}),
    do: [
      "gemini-extension.json",
      ".gemini/commands/controlkeel",
      "skills/controlkeel-governance/SKILL.md",
      "GEMINI.md",
      "README.md"
    ]

  defp default_artifact_surfaces(%{id: "kiro"}),
    do: [
      ".kiro/hooks",
      ".kiro/steering",
      ".kiro/settings",
      ".kiro/commands",
      ".kiro/mcp.json",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "kilo"}),
    do: [
      ".kilo/skills",
      ".kilo/commands",
      ".kilo/kilo.json",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "amp"}),
    do: [
      ".amp/plugins",
      ".agents/skills/controlkeel-governance",
      ".amp/commands",
      ".amp/package.json",
      ".mcp.json",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "augment"}),
    do: [
      ".augment/skills",
      ".augment/agents",
      ".augment/commands",
      ".augment/rules",
      ".augment/mcp.json",
      ".augment/settings.controlkeel.json",
      ".augment-plugin",
      "AGENTS.md",
      "AUGMENT.md",
      "README.md"
    ]

  defp default_artifact_surfaces(%{id: "roo-code"}),
    do: [
      ".roo/skills",
      ".roo/rules",
      ".roo/commands",
      ".roo/guidance",
      ".roomodes",
      ".mcp.json",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "aider"}),
    do: ["AGENTS.md", "AIDER.md", ".aider.conf.yml", ".aider/commands"]

  defp default_artifact_surfaces(%{id: "droid"}),
    do: [
      ".factory/skills",
      ".factory/droids",
      ".factory/commands",
      ".factory/mcp.json",
      ".factory-plugin/plugin.json",
      "mcp.json",
      "README.md",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "open-agents"}),
    do: [
      ".agents/skills",
      "AGENTS.md",
      "controlkeel/dist/open-agents-runtime"
    ]

  defp default_artifact_surfaces(%{support_class: "headless_runtime"}),
    do: ["AGENTS.md", ".mcp.hosted.json", "runtime export bundle"]

  defp default_artifact_surfaces(_attrs), do: []

  defp normalize_id(id) do
    id
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace("_", "-")
  end
end
