# ControlKeel support matrix (canonical)

This document is the **single inventory** for attach targets, MCP tools, and bundled skills. It is maintained to match:

- [`lib/controlkeel/agent_integration.ex`](../lib/controlkeel/agent_integration.ex) — `AgentIntegration.catalog/0`
- [`lib/controlkeel/distribution.ex`](../lib/controlkeel/distribution.ex) — `required_mcp_tools/0`, install channels
- [`lib/controlkeel/mcp/protocol.ex`](../lib/controlkeel/mcp/protocol.ex) — tool schemas exposed to MCP clients
- [`priv/skills/`](../priv/skills/) — on-disk AgentSkills bundles

For install paths and proxy URLs, see [agent-integrations.md](agent-integrations.md) and [getting-started.md](getting-started.md).
Product intent and acceptance criteria for this matrix live in [agent-support-prd.md](agent-support-prd.md) and [agent-support-requirements.md](agent-support-requirements.md).

## Typed integration catalog (`AgentIntegration.catalog/0`)

Every shipped integration row now declares a **support class**:

- `attach_client`
- `headless_runtime`
- `framework_adapter`
- `provider_only`
- `alias`
- `unverified`

Only `attach_client` rows produce real `controlkeel attach <id>` commands. `headless_runtime` rows export runtime bundles, `framework_adapter` rows surface through benchmark/policy tooling, `provider_only` rows surface through CK provider flows, and `alias` rows point at a canonical shipped target.

Attachable and runtime integrations use the **same required MCP tool set** (see below): `ck_context`, `ck_validate`, `ck_finding`, `ck_budget`, `ck_route`, and when skills are enabled, `ck_skill_list` / `ck_skill_load`.

| ID | Support class | Action | Auth mode | MCP mode | Skills mode | Preferred export / bundle |
|----|---------------|--------|-----------|----------|-------------|---------------------------|
| `claude-code` | attach_client | `controlkeel attach claude-code` | `env_bridge` | `native` | `native` | `claude-standalone` |
| `codex-cli` | attach_client | `controlkeel attach codex-cli` | `env_bridge` | `native` | `native` | `codex` |
| `cline` | attach_client | `controlkeel attach cline` | `ck_owned` | `native` | `native` | `cline-native` |
| `roo-code` | attach_client | `controlkeel attach roo-code` | `ck_owned` | `native` | `native` | `roo-native` |
| `goose` | attach_client | `controlkeel attach goose` | `ck_owned` | `native` | `instructions_only` | `goose-native` |
| `vscode` | attach_client | `controlkeel attach vscode` | `ck_owned` | `native` | `native` | `github-repo` |
| `copilot` | attach_client | `controlkeel attach copilot` | `ck_owned` | `native` | `native` | `github-repo` |
| `cursor` | attach_client | `controlkeel attach cursor` | `ck_owned` | `native` | `instructions_only` | `instructions-only` |
| `windsurf` | attach_client | `controlkeel attach windsurf` | `ck_owned` | `native` | `instructions_only` | `instructions-only` |
| `kiro` | attach_client | `controlkeel attach kiro` | `ck_owned` | `native` | `instructions_only` | `instructions-only` |
| `amp` | attach_client | `controlkeel attach amp` | `ck_owned` | `native` | `instructions_only` | `instructions-only` |
| `opencode` | attach_client | `controlkeel attach opencode` | `ck_owned` | `native` | `instructions_only` | `instructions-only` |
| `gemini-cli` | attach_client | `controlkeel attach gemini-cli` | `ck_owned` | `native` | `instructions_only` | `instructions-only` |
| `continue` | attach_client | `controlkeel attach continue` | `ck_owned` | `native` | `instructions_only` | `instructions-only` |
| `aider` | attach_client | `controlkeel attach aider` | `ck_owned` | `native` | `instructions_only` | `instructions-only` |
| `hermes-agent` | attach_client | `controlkeel attach hermes-agent` | `config_reference` | `native` | `native` | `hermes-native` |
| `openclaw` | attach_client | `controlkeel attach openclaw` | `config_reference` | `native` | `plugin_bundle` | `openclaw-native` |
| `droid` | attach_client | `controlkeel attach droid` | `gateway_base_url` | `native` | `native` | `droid-bundle` |
| `forge` | attach_client | `controlkeel attach forge` | `acp_session` | `export_only` | `instructions_only` | `forge-acp` |
| `devin` | headless_runtime | `controlkeel runtime export devin` | `oauth_runtime` | `export_only` | `instructions_only` | `devin-runtime` |
| `open-swe` | headless_runtime | `controlkeel runtime export open-swe` | `ck_owned` | `export_only` | `instructions_only` | `open-swe-runtime` |
| `dspy` | framework_adapter | adapter only | `ck_owned` | `none` | `none` | `framework-adapter` |
| `gepa` | framework_adapter | adapter only | `ck_owned` | `none` | `none` | `framework-adapter` |
| `deepagents` | framework_adapter | adapter only | `ck_owned` | `none` | `none` | `framework-adapter` |
| `fastmcp` | framework_adapter | adapter only | `none` | `none` | `none` | `framework-adapter` |
| `codestral` | provider_only | provider template only | `ck_owned` | `none` | `none` | `provider-profile` |
| `ollama-runtime` | provider_only | provider template only | `local` | `none` | `none` | `provider-profile` |
| `vllm` | provider_only | provider template only | `ck_owned` | `none` | `none` | `provider-profile` |
| `sglang` | provider_only | provider template only | `ck_owned` | `none` | `none` | `provider-profile` |
| `lmstudio` | provider_only | provider template only | `ck_owned` | `none` | `none` | `provider-profile` |
| `huggingface` | provider_only | provider template only | `ck_owned` | `none` | `none` | `provider-profile` |
| `claude-dispatch` | alias | use `claude-code` | `env_bridge` | `native` | `native` | `claude-standalone` |
| `cognition` | alias | use `devin` | `oauth_runtime` | `export_only` | `instructions_only` | `devin-runtime` |
| `codex-app-server` | alias | use `codex-cli` | `env_bridge` | `native` | `native` | `codex` |
| `cursor-agent` | alias | use `cursor` | `ck_owned` | `native` | `instructions_only` | `instructions-only` |
| `copilot-cli` | alias | use `copilot` | `ck_owned` | `native` | `native` | `github-repo` |
| `t3code` | alias | use `codex-cli` | `env_bridge` | `native` | `native` | `codex` |
| `rlm-agent` | unverified | research only | `none` | `none` | `none` | n/a |
| `slate` | unverified | research only | `none` | `none` | `none` | n/a |
| `retune` | unverified | research only | `none` | `none` | `none` | n/a |

The shipped `copilot` attach target is the repo-native path for GitHub Copilot, and the exported `copilot-plugin` bundle is the same companion path used for GitHub Copilot CLI and VS Code agent mode.

Provider-only backends such as `vllm`, `sglang`, `lmstudio`, `huggingface`, and `codestral` currently flow through the CK `openai` provider path with a custom `base_url` and `model`; they are cataloged separately so the support matrix stays honest about the backend you are really targeting.

**Router agent IDs** (for `ck_route` / policy): where set in code, the integration’s `router_agent_id` matches the attach id (e.g. `opencode`, `cursor`); VS Code / Copilot use `nil` in the catalog.

## MCP runtime tools

Implemented under [`lib/controlkeel/mcp/tools/`](../lib/controlkeel/mcp/tools/). The MCP server advertises **five tools always**, and **adds** `ck_skill_list` and `ck_skill_load` when the runtime has a non-empty skill catalog (see `protocol.ex` `tool_schemas/0`).

| Tool | Purpose |
|------|---------|
| `ck_validate` | Run FastPath scan (patterns, Semgrep, optional LLM advisory); optional `session_id` / `task_id`; returns `advisory` metadata when present. |
| `ck_context` | Session/task context: findings summary, budget, production boundary summary, memory hits, resume packet, provider status. Requires `session_id`. |
| `ck_finding` | Record a governed finding for a session (and optional task). |
| `ck_budget` | Budget estimate or commit (`mode`: `estimate` \| `commit`). |
| `ck_route` | Agent routing recommendation from `AgentRouter` (`task`, optional `risk_tier`, `budget_remaining_cents`, `allowed_agents`). |
| `ck_skill_list` | List AgentSkills from the registry (optional `project_root`, `target`, `format`). **Only registered when skills exist.** |
| `ck_skill_load` | Load `SKILL.md` for a named skill. **Only registered when skills exist.** |

Authoritative tool names in code: `ControlKeel.Distribution.required_mcp_tools/0` lists the **core** seven identifiers; the protocol may omit skill tools when no skills are bundled.

## Bundled skills (`priv/skills/`)

These directories ship with the repo and are discovered by [`ControlKeel.Skills.Registry`](../lib/controlkeel/skills/registry.ex):

| Skill directory | Role |
|-----------------|------|
| `agent-integration` | Agent integration workflows and references (e.g. target matrix). |
| `benchmark-operator` | Benchmark operator playbooks. |
| `compliance-audit` | Compliance / control matrix audits. |
| `controlkeel-governance` | Governance workflow references. |
| `cost-optimization` | Budget and cost playbooks. |
| `domain-audit` | Domain-specific review matrices. |
| `policy-training` | Offline policy training / promotion references. |
| `proof-memory` | Proof bundles and typed memory workflow. |
| `security-review` | Security review checklist. |
| `ship-readiness` | Release / ship checklist. |

Export targets on each integration (e.g. `claude-plugin`, `codex`) refer to **CLI** `controlkeel skills export --target …` bundles, not separate MCP tools.

## Adding a new attach target (maintainers)

1. Confirm a **documented** MCP or config file location for that client.
2. Add a new `integration(...)` entry to `AgentIntegration.catalog/0` with accurate `provider_bridge`, `supported_scopes`, and `export_targets`.
3. Wire CLI `attach` for that id if not already present in [`lib/controlkeel/cli.ex`](../lib/controlkeel/cli.ex) (or runtime attach module).
4. Update this matrix and [agent-integrations.md](agent-integrations.md).
5. Add or extend tests for attach behavior where feasible.

Historical research names do **not** automatically get catalog entries. A target becomes shipped support only after it has a documented config surface, a truthful `AgentIntegration` row, CLI/export coverage, docs, and tests.
