defmodule ControlKeel.AgentIntegration do
  @moduledoc false

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
          "Uses the official Claude CLI MCP registration flow and installs native Claude skills by default.",
        attach_command: "controlkeel attach claude-code",
        config_location:
          "Claude CLI local MCP registration (`claude mcp add-json ... --scope local`).",
        companion_delivery:
          "Installs `.claude/skills` and `.claude/agents`; can also export a publishable Claude plugin bundle.",
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
          "Writes MCP config and installs open-standard skills plus a Codex operator agent.",
        attach_command: "controlkeel attach codex-cli",
        config_location:
          "Codex MCP config (`~/.codex/config.json` or project-scoped equivalent).",
        companion_delivery:
          "Installs `.agents/skills` and `.codex/agents`; can also export portable Codex bundles or a Codex plugin.",
        preferred_target: "codex",
        default_scope: "user",
        router_agent_id: "codex-cli",
        auth_mode: "env_bridge",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "openai/codex-cli",
        upstream_docs_url: "https://github.com/openai/codex",
        provider_bridge: %{
          supported: true,
          provider: "openai",
          mode: "env_bridge",
          owner: "agent"
        },
        supported_scopes: ["user", "project"],
        export_targets: ["codex", "codex-plugin", "open-standard"]
      }),
      attach_client(%{
        id: "vscode",
        label: "VS Code agent mode",
        category: "repo-native",
        description:
          "Prepares repository-native skill, agent, and MCP files for VS Code discovery.",
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
        export_targets: ["github-repo", "copilot-plugin"]
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
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "native",
        upstream_slug: "github/copilot",
        upstream_docs_url: "https://docs.github.com/copilot",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["github-repo", "copilot-plugin"]
      }),
      attach_client(%{
        id: "cursor",
        label: "Cursor",
        category: "native-first",
        description:
          "Attaches the MCP server and prepares Cursor-native rules, MCP config, and portable skill bundles for governed repo work.",
        attach_command: "controlkeel attach cursor",
        config_location: "Cursor global MCP config file.",
        companion_delivery:
          "Installs `.agents/skills`, `.cursor/rules`, and `.cursor/mcp.json`; can also export a portable native Cursor bundle.",
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
          "Attaches the MCP server and prepares Windsurf-native rules, MCP config, and portable skill bundles for governed repo work.",
        attach_command: "controlkeel attach windsurf",
        config_location: "Windsurf global MCP config file.",
        companion_delivery:
          "Installs `.agents/skills`, `.windsurf/rules`, and `.windsurf/mcp.json`; can also export a portable native Windsurf bundle.",
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
        category: "mcp-plus-instructions",
        description:
          "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        attach_command: "controlkeel attach kiro",
        config_location: "Kiro MCP config file.",
        companion_delivery:
          "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        preferred_target: "instructions-only",
        default_scope: "project",
        router_agent_id: "kiro",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "instructions_only",
        upstream_slug: "kiro",
        upstream_docs_url: "https://kiro.dev",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["instructions-only"]
      }),
      attach_client(%{
        id: "amp",
        label: "Amp",
        category: "mcp-plus-instructions",
        description:
          "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        attach_command: "controlkeel attach amp",
        config_location: "Amp MCP config file.",
        companion_delivery:
          "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        preferred_target: "instructions-only",
        default_scope: "project",
        router_agent_id: "amp",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "instructions_only",
        upstream_slug: "sourcegraph/amp",
        upstream_docs_url: "https://ampcode.com",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["instructions-only"]
      }),
      attach_client(%{
        id: "opencode",
        label: "OpenCode",
        category: "mcp-plus-instructions",
        description:
          "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        attach_command: "controlkeel attach opencode",
        config_location: "OpenCode MCP config file.",
        companion_delivery:
          "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        preferred_target: "instructions-only",
        default_scope: "project",
        router_agent_id: "opencode",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "instructions_only",
        upstream_slug: "sst/opencode",
        upstream_docs_url: "https://opencode.ai",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["instructions-only"]
      }),
      attach_client(%{
        id: "gemini-cli",
        label: "Gemini CLI",
        category: "mcp-plus-instructions",
        description:
          "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        attach_command: "controlkeel attach gemini-cli",
        config_location: "Gemini CLI MCP config file.",
        companion_delivery:
          "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
        preferred_target: "instructions-only",
        default_scope: "project",
        router_agent_id: "gemini-cli",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "instructions_only",
        upstream_slug: "google-gemini/gemini-cli",
        upstream_docs_url: "https://github.com/google-gemini/gemini-cli",
        provider_bridge: %{supported: false, mode: "ck_owned", owner: "controlkeel"},
        supported_scopes: ["project"],
        export_targets: ["instructions-only"]
      }),
      attach_client(%{
        id: "continue",
        label: "Continue",
        category: "native-first",
        description:
          "Attaches the MCP server and prepares Continue-native skills, prompts, and MCP config for governed repo work.",
        attach_command: "controlkeel attach continue",
        config_location: "Continue MCP config file.",
        companion_delivery:
          "Installs `.continue/skills`, `.continue/prompts`, and `.continue/mcp.json`; can also export a portable native Continue bundle.",
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
        id: "aider",
        label: "Aider",
        category: "mcp-plus-instructions",
        description:
          "Attaches the MCP server and prepares portable instruction snippets for skill-like workflows.",
        attach_command: "controlkeel attach aider",
        config_location: "Aider MCP config file in the current project.",
        companion_delivery:
          "Exports `AGENTS.md`, `CLAUDE.md`, and Copilot-style instruction snippets under `controlkeel/dist/instructions-only`.",
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
          "Registers ControlKeel as an MCP server for Cline and installs Cline-native skills, rules, and workflow guidance.",
        attach_command: "controlkeel attach cline",
        config_location:
          "Cline CLI MCP settings live in `~/.cline/data/settings/cline_mcp_settings.json` or `<CLINE_DIR>/data/settings/cline_mcp_settings.json`; project rules live in `.clinerules/` and project skills in `.cline/skills/`.",
        companion_delivery:
          "Installs `.cline/skills`, emits `.clinerules` guidance plus a workflow, and prepares a Cline MCP config snippet.",
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
          "Installs Roo-native skills, rules, commands, guidance, and `.roomodes` companion files for governed repo work.",
        attach_command: "controlkeel attach roo-code",
        config_location:
          "Roo project companions live in `.roo/skills`, `.roo/rules`, `.roo/commands`, `.roo/guidance`, and `.roomodes` at the repo root.",
        companion_delivery:
          "Installs `.roo/skills`, emits repo-native rules, commands, guidance, and a ControlKeel `.roomodes` mode.",
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
          "Registers ControlKeel as a Goose MCP extension and installs project-native `.goosehints` and workflow companions.",
        attach_command: "controlkeel attach goose",
        config_location:
          "Goose custom extensions live in `~/.config/goose/config.yaml`; project context lives in `.goosehints`, `AGENTS.md`, and optional `goose/workflow_recipes/` files.",
        companion_delivery:
          "Merges a ControlKeel Goose extension into the user Goose config and writes repo-local `.goosehints`, workflow recipe, and MCP companion files.",
        preferred_target: "goose-native",
        default_scope: "project",
        router_agent_id: "goose",
        auth_mode: "ck_owned",
        mcp_mode: "native",
        skills_mode: "instructions_only",
        upstream_slug: "block/goose",
        upstream_docs_url: "https://block.github.io/goose/docs/getting-started/using-extensions/",
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
          "Generates `.factory` skills, droids, commands, and MCP config aligned with Droid's user/project hierarchy.",
        attach_command: "controlkeel attach droid",
        config_location:
          "Factory settings live in `~/.factory/settings.json` or `<repo>/.factory/settings.local.json`; MCP config is layered through `~/.factory/mcp.json` and `<repo>/.factory/mcp.json`.",
        companion_delivery:
          "Installs `.factory/skills`, `.factory/droids`, `.factory/commands`, and `.factory/mcp.json` bundles for user or project scope.",
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
        export_targets: ["droid-bundle"]
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
        id: "codex-app-server",
        label: "Codex app / app server surface",
        category: "alias",
        description:
          "Alias to the shipped Codex CLI path; ControlKeel currently supports Codex through the documented Codex CLI / shared MCP config surface.",
        alias_of: "codex-cli",
        auth_mode: "env_bridge",
        upstream_slug: "openai/codex",
        upstream_docs_url: "https://github.com/openai/codex",
        supported_scopes: ["user", "project"],
        preferred_target: "codex",
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
        id: "t3code",
        label: "T3 Chat / T3 Code wrapper",
        category: "alias",
        description:
          "Wrapper/alias path until a stable native integration surface exists. Prefer Codex CLI or Claude Code underneath.",
        alias_of: "codex-cli",
        auth_mode: "env_bridge",
        upstream_slug: "t3chat/t3-code",
        upstream_docs_url: "https://t3.chat",
        supported_scopes: ["user", "project"],
        preferred_target: "codex",
        export_targets: ["codex", "codex-plugin", "open-standard"]
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

  def auth_owner(%__MODULE__{provider_bridge: %{owner: owner}}) when is_binary(owner), do: owner
  def auth_owner(%__MODULE__{auth_mode: "ck_owned"}), do: "controlkeel"
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
      supported_scopes: attrs[:supported_scopes] || [],
      required_mcp_tools:
        if(attrs[:support_class] in ["framework_adapter", "provider_only", "unverified"],
          do: [],
          else: Distribution.required_mcp_tools()
        ),
      install_channels: install_channels,
      export_targets: attrs[:export_targets] || []
    }
  end

  defp default_agent_uses_ck_via(attrs) do
    case attrs[:id] do
      id when id in ["claude-code", "claude-dispatch"] ->
        ["local_mcp", "plugin", "native_skills"]

      id when id in ["codex-cli", "codex-app-server", "t3code"] ->
        ["local_mcp", "plugin", "native_skills"]

      id when id in ["vscode", "copilot", "copilot-cli"] ->
        ["local_mcp", "plugin", "native_skills", "workflows", "hooks"]

      id when id in ["cursor", "cursor-agent", "windsurf"] ->
        ["local_mcp", "native_skills", "rules"]

      id when id in ["cline", "continue", "roo-code"] ->
        ["local_mcp", "native_skills", "rules", "workflows"]

      "goose" ->
        ["local_mcp", "workflows", "hooks"]

      id when id in ["hermes-agent", "openclaw"] ->
        ["local_mcp", "plugin", "native_skills"]

      id when id in ["kiro", "amp", "aider", "opencode", "gemini-cli"] ->
        ["local_mcp", "rules"]

      id when id in ["forge", "devin", "open-swe"] ->
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
             "aider",
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

  defp normalize_id(id) do
    id
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace("_", "-")
  end
end
