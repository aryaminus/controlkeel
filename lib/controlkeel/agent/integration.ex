defmodule ControlKeel.Agent.Integration do
  @moduledoc false

  alias ControlKeel.Ops.Distribution

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
    :runtime_provider_hint,
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
        export_targets: ["claude-standalone", "claude-plugin"],
        submission_mode: "hook",
        feedback_mode: "command_reply",
        artifact_surfaces: [
          "skills/",
          "agents/controlkeel-operator.md",
          ".claude-plugin/plugin.json",
          "hooks/hooks.json",
          "hooks/controlkeel-review.sh",
          "hooks/controlkeel-review.ps1",
          "settings.json",
          ".mcp.json"
        ],
        runtime_transport: "claude_agent_sdk",
        runtime_auth_owner: "agent",
        runtime_session_support: %{
          "create" => true,
          "fork" => true,
          "resume" => true,
          "streaming" => true
        },
        runtime_review_transport: "hook_sdk",
        runtime_capabilities: %{
          policy_gate: true,
          tool_approval: true,
          user_input_pause_resume: true,
          deterministic_event_ids: false,
          replay_safe_delivery: false
        },
        runtime_provider_hint: %{
          "provider" => "anthropic",
          "source" => "agent_runtime",
          "auth_mode" => "env_bridge",
          "auth_owner" => "agent"
        }
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
        submission_mode: "command",
        feedback_mode: "command_reply",
        phase_model: "review_only",
        export_targets: ["codex", "codex-plugin", "open-standard"],
        artifact_surfaces: [
          ".agents/skills",
          ".codex/config.toml",
          ".codex/hooks.json",
          ".codex/hooks",
          ".codex/agents/controlkeel-operator.toml",
          ".codex/agents/controlkeel-reviewer.toml",
          ".codex/agents/controlkeel-docs-researcher.toml",
          ".codex/commands/controlkeel-review.md",
          ".codex/commands/controlkeel-annotate.md",
          ".codex/commands/controlkeel-last.md",
          ".codex/commands/controlkeel-diff-review.md",
          ".codex/commands/controlkeel-completion-review.md",
          ".mcp.json",
          "AGENTS.md"
        ],
        runtime_transport: "codex_sdk",
        runtime_auth_owner: "agent",
        runtime_session_support: %{
          "create" => true,
          "fork" => false,
          "resume" => true,
          "streaming" => true
        },
        runtime_review_transport: "command_thread",
        runtime_capabilities: %{
          policy_gate: true,
          tool_approval: false,
          user_input_pause_resume: false,
          deterministic_event_ids: false,
          replay_safe_delivery: false
        },
        runtime_provider_hint: %{
          "provider" => "openai",
          "source" => "agent_runtime",
          "auth_mode" => "agent_runtime",
          "auth_owner" => "agent"
        }
      }),
      attach_client(%{
        id: "vscode",
        label: "VS Code agent mode",
        category: "repo-native",
        description:
          "Prepares repository-native skill, agent, and MCP files for VS Code agent mode discovery.",
        attach_command: "controlkeel attach vscode",
        config_location: "Repository MCP config in `.github/mcp.json` and `.vscode/mcp.json`.",
        companion_delivery:
          "Writes `.github/skills`, `.github/agents`, and repo MCP config; can also export a Copilot / VS Code plugin bundle.",
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
        export_targets: ["github-repo", "copilot-plugin"],
        submission_mode: "command",
        artifact_surfaces: [
          ".agents/skills",
          ".github/agents",
          ".github/mcp.json",
          ".vscode/mcp.json"
        ]
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
        export_targets: ["github-repo", "copilot-plugin"],
        review_experience: "native_review",
        artifact_surfaces: [
          ".agents/skills",
          ".github/agents",
          ".github/mcp.json",
          ".github/copilot-instructions.md",
          ".github/commands/controlkeel-plan-review.md",
          ".vscode/mcp.json",
          "plugin.json",
          "hooks.json"
        ],
        runtime_transport: "hook_session_parser",
        runtime_auth_owner: "agent",
        runtime_session_support: %{
          "create" => false,
          "fork" => false,
          "resume" => false,
          "streaming" => false
        },
        runtime_review_transport: "hook_session_state",
        runtime_capabilities: %{
          policy_gate: true,
          tool_approval: false,
          user_input_pause_resume: false,
          deterministic_event_ids: false,
          replay_safe_delivery: false
        },
        runtime_provider_hint: %{
          "provider" => "openai",
          "source" => "agent_runtime",
          "auth_mode" => "agent_runtime",
          "auth_owner" => "agent"
        }
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
        router_agent_id: nil,
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["pi-native"],
        review_experience: "browser_review",
        submission_mode: "command",
        feedback_mode: "command_reply",
        artifact_surfaces: [
          ".agents/skills",
          ".pi/controlkeel.json",
          ".pi/commands/controlkeel-review.md",
          ".pi/commands/controlkeel-submit-plan.md",
          ".pi/mcp.json",
          "pi-extension.json",
          "package.json",
          "README.md",
          "PI.md"
        ],
        runtime_transport: "pi_rpc",
        runtime_auth_owner: "agent",
        runtime_session_support: %{
          "create" => true,
          "fork" => false,
          "resume" => false,
          "streaming" => true
        },
        runtime_review_transport: "extension_rpc",
        runtime_capabilities: %{
          policy_gate: true,
          tool_approval: false,
          user_input_pause_resume: false,
          deterministic_event_ids: false,
          replay_safe_delivery: false
        },
        runtime_provider_hint: %{
          "provider" => "pi_connected",
          "source" => "agent_runtime",
          "auth_mode" => "agent_runtime",
          "auth_owner" => "agent"
        }
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
        export_targets: ["cursor-native"]
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
        export_targets: ["windsurf-native"]
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
        export_targets: ["kiro-native"]
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
        router_agent_id: nil,
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "Kilo-Org/kilocode",
        upstream_docs_url: "https://kilo.ai/docs",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["kilo-native"]
      }),
      attach_client(%{
        id: "amp",
        label: "Amp",
        category: "native-first",
        description:
          "Attaches MCP server and delivers native governance for Amp Neo via TypeScript Plugin API hooks, MCP, custom tools, commands, and a portable skill bundle.",
        attach_command: "controlkeel attach amp",
        config_location:
          "Amp MCP config plus project `.amp/plugins/` and `.amp/commands/` for Neo plugin-powered governance.",
        companion_delivery:
          "Exports a Neo-compatible governance TypeScript plugin with `amp.on` permission hooks, CK validation tools, commands, a native `controlkeel-governance` skill bundle, package scaffold, and `AGENTS.md` instructions.",
        preferred_target: "amp-native",
        default_scope: "project",
        router_agent_id: "amp",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "sourcegraph/amp",
        upstream_docs_url: "https://ampcode.com/manual/plugin-api",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["amp-native"]
      }),
      attach_client(%{
        id: "augment",
        label: "Augment / Auggie CLI",
        category: "native-first",
        description:
          "Attaches MCP server and delivers native governance via Auggie workspace commands, subagents, rules, and ACP-compatible runtime transport.",
        attach_command: "controlkeel attach augment",
        config_location:
          "Workspace assets under `.augment/`; persistent MCP and permission settings live in `~/.augment/settings.json` when configured outside a plugin.",
        companion_delivery:
          "Exports `.augment/skills`, `.augment/agents`, `.augment/commands`, `.augment/rules`, `.augment/mcp.json`, a settings snippet, and an MCP bridge.",
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
        export_targets: ["augment-native"],
        artifact_surfaces: [
          ".agents/skills/controlkeel-governance/SKILL.md",
          ".augment/agents/controlkeel-operator.md",
          ".augment/commands/controlkeel-review.md",
          ".augment/commands/controlkeel-submit-plan.md",
          ".augment/commands/controlkeel-annotate.md",
          ".augment/commands/controlkeel-last.md",
          ".augment/rules/controlkeel.md",
          ".augment/mcp.json",
          ".augment/settings.controlkeel.json",
          "AGENTS.md",
          "AUGMENT.md",
          "README.md"
        ],
        runtime_transport: "auggie_sdk_acp",
        runtime_auth_owner: "agent",
        runtime_session_support: %{
          "create" => true,
          "fork" => false,
          "resume" => true,
          "streaming" => true
        },
        runtime_review_transport: "mcp_tool_call",
        runtime_capabilities: %{
          policy_gate: true,
          tool_approval: true,
          user_input_pause_resume: false,
          deterministic_event_ids: false,
          replay_safe_delivery: false
        },
        runtime_provider_hint: %{
          "provider" => "augment_runtime",
          "source" => "agent_runtime",
          "auth_mode" => "agent_runtime",
          "auth_owner" => "agent"
        }
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
        export_targets: ["opencode-native"],
        feedback_mode: "command_reply",
        artifact_surfaces: [
          ".agents/skills",
          ".opencode/plugins/controlkeel-governance.ts",
          ".opencode/agents/controlkeel-operator.md",
          ".opencode/commands/controlkeel-review.md",
          ".opencode/commands/controlkeel-submit-plan.md",
          ".opencode/mcp.json",
          "package.json",
          "index.js",
          "README.md",
          "AGENTS.md"
        ],
        runtime_transport: "opencode_sdk",
        runtime_auth_owner: "agent",
        runtime_session_support: %{
          "create" => true,
          "fork" => true,
          "resume" => true,
          "streaming" => true
        },
        runtime_review_transport: "plugin_session_tool",
        runtime_capabilities: %{
          policy_gate: true,
          tool_approval: true,
          user_input_pause_resume: false,
          deterministic_event_ids: false,
          replay_safe_delivery: false
        },
        runtime_provider_hint: %{
          "provider" => "opencode_connected",
          "source" => "agent_runtime",
          "auth_mode" => "agent_runtime",
          "auth_owner" => "agent"
        }
      }),
      alias_entry(%{
        id: "gemini-cli",
        label: "Gemini CLI",
        category: "alias",
        description:
          "Gemini CLI is moving to Antigravity CLI. Attaching it installs the Antigravity CLI integration, which reads `.agents/skills`, `.agents/mcp_config.json`, and `AGENTS.md`.",
        alias_of: "antigravity-cli",
        auth_mode: "ck_owned",
        upstream_slug: "google-gemini/gemini-cli",
        upstream_docs_url: "https://github.com/google-gemini/gemini-cli",
        supported_scopes: ["project", "export"],
        preferred_target: "antigravity-cli-native",
        export_targets: ["antigravity-cli-native"]
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
        export_targets: ["continue-native"]
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
        router_agent_id: nil,
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "letta-ai/letta-code",
        upstream_docs_url: "https://docs.letta.com/letta-code/cli-reference",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project", "export"],
        export_targets: ["letta-code-native"]
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
        router_agent_id: nil,
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
        router_agent_id: nil,
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
        router_agent_id: nil,
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
        id: "droid",
        label: "Factory Droid",
        category: "native-first",
        description:
          "Generates repo-local `.factory` skills, droids, commands, and MCP config aligned with Droid's user/project hierarchy.",
        attach_command: "controlkeel attach droid",
        config_location:
          "Factory settings live in `~/.factory/settings.json` or `<repo>/.factory/settings.local.json`; MCP config is layered through `~/.factory/mcp.json` and `<repo>/.factory/mcp.json`.",
        companion_delivery:
          "Installs `.factory/skills`, `.factory/droids`, `.factory/commands`, and `.factory/mcp.json` bundles for user or project scope.",
        preferred_target: "droid-bundle",
        default_scope: "project",
        router_agent_id: nil,
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
        export_targets: ["droid-bundle"]
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
        router_agent_id: nil,
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
        router_agent_id: nil,
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
        export_targets: ["cursor-native"]
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
        router_agent_id: nil,
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
        export_targets: ["codex", "codex-plugin", "open-standard"],
        runtime_transport: "codex_app_server_json_rpc",
        runtime_auth_owner: "agent",
        runtime_session_support: %{
          "create" => true,
          "fork" => true,
          "resume" => true,
          "streaming" => true
        },
        runtime_review_transport: "app_server_review",
        runtime_capabilities: %{
          policy_gate: true,
          tool_approval: true,
          user_input_pause_resume: true,
          deterministic_event_ids: true,
          replay_safe_delivery: true
        },
        runtime_provider_hint: %{
          "provider" => "openai",
          "source" => "agent_runtime",
          "auth_mode" => "agent_runtime",
          "auth_owner" => "agent"
        }
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
        id: "gemini",
        label: "Gemini",
        category: "alias",
        description:
          "Alias to the Antigravity CLI integration for skill ecosystems that label the agent surface as Gemini.",
        alias_of: "antigravity-cli",
        auth_mode: "ck_owned",
        upstream_slug: "google-gemini/gemini-cli",
        upstream_docs_url: "https://github.com/google-gemini/gemini-cli",
        supported_scopes: ["project", "export"],
        preferred_target: "antigravity-cli-native",
        export_targets: ["antigravity-cli-native"]
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
        export_targets: ["kiro-native"]
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
        export_targets: ["roo-native"]
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
        router_agent_id: nil,
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "pingdotgg/t3code",
        upstream_docs_url: "https://github.com/pingdotgg/t3code",
        provider_bridge: %{supported: true, mode: "agent_runtime", owner: "agent"},
        supported_scopes: ["user", "project"],
        export_targets: ["codex", "codex-plugin", "open-standard"],
        runtime_transport: "t3code_provider_runtime",
        runtime_auth_owner: "agent",
        runtime_session_support: %{
          "create" => true,
          "fork" => true,
          "resume" => true,
          "streaming" => true
        },
        runtime_review_transport: "orchestration_domain_event",
        runtime_capabilities: %{
          policy_gate: true,
          tool_approval: true,
          user_input_pause_resume: true,
          deterministic_event_ids: true,
          replay_safe_delivery: true
        },
        runtime_provider_hint: %{
          "provider" => "provider_neutral",
          "source" => "agent_runtime",
          "auth_mode" => "agent_runtime",
          "auth_owner" => "agent"
        }
      }),
      attach_client(%{
        id: "antigravity-cli",
        label: "Antigravity CLI (AGY)",
        category: "native-first",
        description:
          "Attaches MCP server and delivers native governance via Antigravity CLI plugins, skills, agents, hooks, rules, and MCP config. AGY is the terminal-first surface of the Antigravity ecosystem with full plugin support.",
        attach_command: "controlkeel attach antigravity-cli",
        config_location:
          "Antigravity CLI config lives in ~/.gemini/antigravity-cli/ (settings.json, mcp_config.json). Workspace config uses .agents/ (skills, rules, hooks, mcp_config.json). Global plugins live in ~/.gemini/config/plugins/.",
        companion_delivery:
          "Installs .agents/skills, .agents/rules, .agents/hooks.json, .agents/mcp_config.json, AGENTS.md, GEMINI.md, and a .agents/plugins/controlkeel/ plugin bundle with manifest, agents, skills, rules, hooks, and MCP config.",
        preferred_target: "antigravity-cli-native",
        default_scope: "project",
        router_agent_id: "antigravity",
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "google/antigravity-cli",
        upstream_docs_url: "https://antigravity.google/docs/cli",
        provider_bridge: %{
          supported: true,
          provider: "google",
          mode: "agent_runtime",
          owner: "agent"
        },
        supported_scopes: ["project"],
        export_targets: ["antigravity-cli-native"],
        review_experience: "native_review",
        submission_mode: "tool_call",
        feedback_mode: "tool_call",
        phase_model: "host_plan_mode"
      }),
      attach_client(%{
        id: "antigravity-ide",
        label: "Antigravity 2.0 IDE",
        category: "native-first",
        description:
          "Prepares Antigravity 2.0 IDE workspace-native skills, rules, hooks, MCP config, and a distributable plugin bundle for governed repo work. Shares the same .agents/ workspace structure as Antigravity CLI.",
        attach_command: "controlkeel attach antigravity-ide",
        config_location:
          "Antigravity IDE config lives in ~/.gemini/antigravity/ (mcp_config.json, skills/). Workspace config uses .agents/ (skills, rules, hooks, mcp_config.json). Global plugins live in ~/.gemini/config/plugins/.",
        companion_delivery:
          "Installs .agents/skills, .agents/rules, .agents/hooks.json, .agents/mcp_config.json, AGENTS.md, GEMINI.md, and a .agents/plugins/controlkeel/ plugin bundle.",
        preferred_target: "antigravity-cli-native",
        default_scope: "project",
        router_agent_id: "antigravity",
        auth_mode: "agent_runtime",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "google/antigravity",
        upstream_docs_url: "https://antigravity.google/docs",
        provider_bridge: %{
          supported: true,
          provider: "google",
          mode: "agent_runtime",
          owner: "agent"
        },
        supported_scopes: ["project"],
        export_targets: ["antigravity-cli-native"],
        review_experience: "browser_review",
        submission_mode: "command",
        feedback_mode: "command_reply",
        phase_model: "host_plan_mode"
      })
    ]
  end

  def attach_catalog do
    Enum.filter(catalog(), &attachable?/1)
  end

  def attachable_ids, do: Enum.map(attach_catalog(), & &1.id)

  @doc """
  Resolves an attach or detach name to the attach client that handles it.
  Aliases such as `codex`, `gemini-cli`, or `roo` resolve to their canonical
  attach client; unknown names return `nil`.
  """
  def resolve_attach_id(id) when is_binary(id) do
    case get(id) do
      %__MODULE__{} = integration ->
        if attachable?(integration) do
          integration.id
        else
          case integration.alias_of && get(integration.alias_of) do
            %__MODULE__{} = target -> if attachable?(target), do: target.id
            _ -> nil
          end
        end

      _ ->
        nil
    end
  end

  def resolve_attach_id(_id), do: nil

  def product_catalog do
    catalog()
    |> Enum.filter(&product_supported?/1)
  end

  @doc """
  Return the one-line copy-paste MCP install command for a host, when one is
  natively supported. This is the "Path B" install — registers ControlKeel as
  an MCP server without running `controlkeel attach`, so the user gets the
  tool surface but not hooks/skills/AGENTS.md.

  Returns `nil` for hosts where there is no canonical one-liner (the user
  must edit a config file manually). Callers should fall back to
  `integration.attach_command` (the "Path A" install) for full setup.
  """
  @spec mcp_install_command(String.t() | nil) :: String.t() | nil
  def mcp_install_command(host_id) do
    case normalize_id(host_id) do
      "claude-code" ->
        "claude mcp add-json controlkeel '{\"command\":\"controlkeel\",\"args\":[\"mcp\"]}' --scope local"

      "opencode" ->
        "opencode mcp add controlkeel controlkeel mcp"

      "cursor" ->
        ~s({"mcpServers":{"controlkeel":{"command":"controlkeel","args":["mcp"]}}})

      "codex-cli" ->
        # TOML snippet; user must append to ~/.codex/config.toml manually.
        "[mcp_servers.controlkeel]\ncommand = \"controlkeel\"\nargs = [\"mcp\"]"

      "vscode" ->
        ~s({"servers":{"controlkeel":{"command":"controlkeel","args":["mcp"]}}})

      "copilot" ->
        ~s({"servers":{"controlkeel":{"command":"controlkeel","args":["mcp"]}}})

      _ ->
        nil
    end
  end

  def runtime_export_catalog do
    Enum.filter(catalog(), &(&1.support_class == "headless_runtime"))
  end

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

  def product_supported?(%__MODULE__{support_class: support_class})
      when support_class in ["attach_client", "headless_runtime"],
      do: true

  def product_supported?(_integration), do: false

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
      required_mcp_tools: Distribution.required_mcp_tools(),
      install_channels: install_channels,
      export_targets: attrs[:export_targets] || [],
      runtime_transport: attrs[:runtime_transport],
      runtime_auth_owner: attrs[:runtime_auth_owner],
      runtime_session_support: attrs[:runtime_session_support] || %{},
      runtime_review_transport: attrs[:runtime_review_transport],
      runtime_capabilities: attrs[:runtime_capabilities] || %{},
      runtime_provider_hint: attrs[:runtime_provider_hint]
    }
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

  defp default_cost_profile(_attrs, "agent"), do: "host_subscription_or_agent_metered"
  defp default_cost_profile(_attrs, "controlkeel"), do: "ck_budget_metered"
  defp default_cost_profile(_attrs, "workspace"), do: "workspace_subscription"
  defp default_cost_profile(_attrs, _auth_owner), do: "unknown"

  defp default_performance_profile("headless_runtime", _execution_support),
    do: "background_runtime"

  defp default_performance_profile(_support_class, "direct"), do: "interactive_direct"
  defp default_performance_profile(_support_class, "handoff"), do: "human_handoff"
  defp default_performance_profile(_support_class, "runtime"), do: "background_runtime"
  defp default_performance_profile(_support_class, _execution_support), do: "manual"

  defp default_token_pressure_profile(_attrs, auth_owner) do
    cond do
      auth_owner == "agent" -> "host_quota_sensitive"
      auth_owner == "workspace" -> "workspace_quota_sensitive"
      true -> "ck_budget_sensitive"
    end
  end

  defp default_time_profile("headless_runtime", _execution_support), do: "long_running_ok"
  defp default_time_profile(_support_class, "direct"), do: "fast_feedback"
  defp default_time_profile(_support_class, "handoff"), do: "checkpoint_driven"
  defp default_time_profile(_support_class, "runtime"), do: "long_running_ok"
  defp default_time_profile(_support_class, _execution_support), do: "manual"

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

      "droid" ->
        ["local_mcp", "native_skills", "commands"]

      "kiro" ->
        ["local_mcp", "native_skills", "hooks", "rules", "commands"]

      "amp" ->
        [
          "local_mcp",
          "plugin",
          "native_skills",
          "commands",
          "tool_call",
          "remote_control",
          "queue_steer",
          "auto_compaction"
        ]

      "augment" ->
        ["local_mcp", "native_skills", "rules", "commands"]

      "devin-terminal" ->
        ["local_mcp", "native_skills", "rules", "hooks"]

      "warp" ->
        ["local_mcp", "native_skills", "rules"]

      "opencode" ->
        ["local_mcp", "plugin", "native_skills", "rules", "commands"]

      "pi" ->
        ["local_mcp", "native_skills", "commands", "rules"]

      id when id in ["devin"] ->
        ["hosted_mcp", "a2a"]

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
             "augment",
             "opencode"
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
             "droid"
           ] ->
        "handoff"

      id when id in ["devin"] ->
        "runtime"

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
       when support_class == "alias" do
    "fallback"
  end

  defp default_install_experience(_attrs), do: "first_class"

  defp default_review_experience(%{id: id})
       when id in [
              "claude-code",
              "opencode",
              "windsurf",
              "cline",
              "kiro",
              "amp",
              "devin-terminal",
              "warp",
              "letta-code"
            ] do
    "native_review"
  end

  defp default_review_experience(%{support_class: "attach_client"}), do: "browser_review"
  defp default_review_experience(%{support_class: "headless_runtime"}), do: "browser_review"
  defp default_review_experience(_attrs), do: "feedback_only"

  defp default_submission_mode(%{id: id})
       when id in ["claude-code", "amp", "augment", "opencode", "devin-terminal", "warp"] do
    "tool_call"
  end

  defp default_submission_mode(%{id: id})
       when id in ["vscode", "copilot", "windsurf", "cline", "kiro", "letta-code"] do
    "hook"
  end

  defp default_submission_mode(%{id: id})
       when id in ["cursor", "continue", "roo-code", "goose", "pi"] do
    "command"
  end

  defp default_submission_mode(%{id: "t3code"}), do: "tool_call"

  defp default_submission_mode(%{support_class: "headless_runtime"}), do: "file_watch"
  defp default_submission_mode(_attrs), do: "manual"

  defp default_feedback_mode(%{support_class: "unverified"}), do: "manual"

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
              "roo-code"
            ] do
    "command_reply"
  end

  defp default_feedback_mode(_attrs), do: "command_reply"

  defp default_plan_phase_support(%{support_class: "unverified"}) do
    []
  end

  defp default_plan_phase_support(%{support_class: "framework_adapter"}),
    do: ["planning", "review"]

  defp default_plan_phase_support(_attrs), do: ["planning", "review", "execution"]

  defp default_confidence_level(%{support_class: "unverified"}), do: "research"
  defp default_confidence_level(%{support_class: "framework_adapter"}), do: "experimental"
  defp default_confidence_level(_attrs), do: "shipped"

  defp default_phase_model(%{support_class: "unverified"}), do: "review_only"
  defp default_phase_model(%{support_class: "framework_adapter"}), do: "review_only"
  defp default_phase_model(%{id: "pi"}), do: "file_plan_mode"
  defp default_phase_model(%{id: "codex-cli"}), do: "review_only"
  defp default_phase_model(%{id: "t3code"}), do: "review_only"
  defp default_phase_model(%{id: "vscode"}), do: "review_only"

  defp default_phase_model(%{id: id}) when id in ["goose", "roo-code"],
    do: "review_only"

  defp default_phase_model(%{support_class: "attach_client"}), do: "host_plan_mode"
  defp default_phase_model(_attrs), do: "review_only"

  defp default_browser_embed(%{support_class: "attach_client"}), do: "external"
  defp default_browser_embed(_attrs), do: "none"

  defp default_subagent_visibility(%{id: id})
       when id in ["claude-code", "copilot", "opencode", "codex-cli", "t3code", "pi"] do
    "primary_only"
  end

  defp default_subagent_visibility(%{id: "vscode"}), do: "none"
  defp default_subagent_visibility(%{support_class: "attach_client"}), do: "all"
  defp default_subagent_visibility(_attrs), do: "none"

  defp default_package_outputs(%{id: "claude-code"}) do
    [
      %{
        "kind" => "release_bundle",
        "name" => "claude-plugin",
        "artifact" => "controlkeel-claude-plugin.tar.gz"
      }
    ]
  end

  defp default_package_outputs(%{id: "augment"}) do
    [
      %{
        "kind" => "release_bundle",
        "name" => "augment-native",
        "artifact" => "controlkeel-augment-native.tar.gz"
      }
    ]
  end

  defp default_package_outputs(%{id: "codex-cli"}) do
    [
      %{
        "kind" => "release_bundle",
        "name" => "codex",
        "artifact" => "controlkeel-codex.tar.gz"
      },
      %{
        "kind" => "release_bundle",
        "name" => "codex-plugin",
        "artifact" => "controlkeel-codex-plugin.tar.gz"
      }
    ]
  end

  defp default_package_outputs(%{id: "copilot"}) do
    [
      %{
        "kind" => "release_bundle",
        "name" => "copilot-plugin",
        "artifact" => "controlkeel-copilot-plugin.tar.gz"
      }
    ]
  end

  defp default_package_outputs(%{id: "opencode"}) do
    [
      %{
        "kind" => "release_bundle",
        "name" => "opencode-native",
        "artifact" => "controlkeel-opencode-native.tar.gz"
      },
      %{
        "kind" => "npm_package",
        "name" => "@aryaminus/controlkeel-opencode",
        "artifact" => "controlkeel-opencode-native.tgz"
      }
    ]
  end

  defp default_package_outputs(%{id: "pi"}) do
    [
      %{
        "kind" => "release_bundle",
        "name" => "pi-native",
        "artifact" => "controlkeel-pi-native.tar.gz"
      },
      %{
        "kind" => "npm_package",
        "name" => "@aryaminus/controlkeel-pi-extension",
        "artifact" => "controlkeel-pi-native.tgz"
      }
    ]
  end

  defp default_package_outputs(%{id: "vscode"}) do
    [
      %{
        "kind" => "release_bundle",
        "name" => "github-repo",
        "artifact" => "controlkeel-github-repo.tar.gz"
      }
    ]
  end

  defp default_package_outputs(_attrs), do: []

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
      direct_install("ck_attach", "CK attach", "controlkeel attach vscode")
    ]
  end

  defp default_direct_install_methods(%{id: "kilo"}) do
    [direct_install("ck_attach", "CK attach", "controlkeel attach kilo")]
  end

  defp default_direct_install_methods(%{id: "amp"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach amp"),
      direct_install(
        "local_plugin",
        "Amp Neo plugin",
        "cp -R ./controlkeel/dist/amp-native/.amp ./"
      )
    ]
  end

  defp default_direct_install_methods(%{id: "augment"}) do
    [
      direct_install("ck_attach", "CK attach", "controlkeel attach augment"),
      direct_install("host_cli", "Install Auggie CLI", "npm install -g @augmentcode/auggie")
    ]
  end

  defp default_direct_install_methods(%{id: "letta-code"}) do
    [
      direct_install("npm_cli", "Letta Code via npm", "npm install -g @letta-ai/letta-code"),
      direct_install("ck_attach", "CK attach", "controlkeel attach letta-code")
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
              "droid",
              "devin-terminal"
            ] do
    [direct_install("ck_attach", "CK attach", "controlkeel attach #{id}")]
  end

  defp default_direct_install_methods(%{support_class: "headless_runtime"}), do: []
  defp default_direct_install_methods(%{support_class: "framework_adapter"}), do: []
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
      ".agents/skills",
      ".github/agents",
      ".github/commands",
      ".github/mcp.json",
      ".github/copilot-instructions.md",
      ".vscode/mcp.json"
    ]
  end

  defp default_artifact_surfaces(%{id: "cursor"}),
    do: [
      ".agents/skills",
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
      ".agents/skills",
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
      ".agents/skills",
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
      ".devin/config.json",
      ".devin/hooks.v1.json",
      ".devin/hooks",
      ".agents/skills",
      ".devin/agents",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "warp"}),
    do: [
      ".agents/skills",
      ".warp/controlkeel-mcp.json",
      ".warp/README.md",
      "AGENTS.md"
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
      ".agents/skills",
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
      "Amp Neo remote control",
      "Amp Neo queue/steer",
      "Amp Neo auto-compaction",
      "Amp Neo compaction provenance tracking",
      "Amp Neo CK-gated remote-control commands",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "augment"}),
    do: [
      ".agents/skills",
      ".augment/agents",
      ".augment/commands",
      ".augment/rules",
      ".augment/mcp.json",
      ".augment/settings.controlkeel.json",
      "AGENTS.md",
      "AUGMENT.md",
      "README.md"
    ]

  defp default_artifact_surfaces(%{id: "roo-code"}),
    do: [
      ".agents/skills",
      ".roo/rules",
      ".roo/commands",
      ".roo/guidance",
      ".roomodes",
      ".mcp.json",
      "AGENTS.md"
    ]

  defp default_artifact_surfaces(%{id: "droid"}),
    do: [
      ".agents/skills",
      ".factory/droids",
      ".factory/commands",
      ".factory/mcp.json",
      "mcp.json",
      "README.md",
      "AGENTS.md"
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
