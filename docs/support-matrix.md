# ControlKeel support matrix (canonical)

This document is the **single inventory** for attach targets, MCP tools, and bundled skills. It is maintained to match:

- [`lib/controlkeel/agent_integration.ex`](../lib/controlkeel/agent_integration.ex) — `AgentIntegration.catalog/0`
- [`lib/controlkeel/distribution.ex`](../lib/controlkeel/distribution.ex) — `required_mcp_tools/0`, install channels
- [`lib/controlkeel/mcp/protocol.ex`](../lib/controlkeel/mcp/protocol.ex) — tool schemas exposed to MCP clients
- [`priv/skills/`](../priv/skills/) — on-disk AgentSkills bundles

For install paths and proxy URLs, see [agent-integrations.md](agent-integrations.md) and [getting-started.md](getting-started.md).

## Attach targets (`AgentIntegration.catalog/0`)

Every integration uses the **same required MCP tool set** (see below): `ck_context`, `ck_validate`, `ck_finding`, `ck_budget`, `ck_route`, and when skills are enabled, `ck_skill_list` / `ck_skill_load`.

| ID | Category | Attach command | Provider bridge | Default scope | Preferred export / bundle | Export targets (labels) |
|----|----------|----------------|-----------------|---------------|---------------------------|-------------------------|
| `claude-code` | native-first | `controlkeel attach claude-code` | Anthropic (environment) | user | `claude-standalone` | `claude-standalone`, `claude-plugin` |
| `codex-cli` | native-first | `controlkeel attach codex-cli` | OpenAI (environment) | user | `codex` | `codex`, `open-standard` |
| `vscode` | repo-native | `controlkeel attach vscode` | none | project | `github-repo` | `github-repo`, `copilot-plugin` |
| `copilot` | repo-native | `controlkeel attach copilot` | none | project | `github-repo` | `github-repo`, `copilot-plugin` |
| `cursor` | mcp-plus-instructions | `controlkeel attach cursor` | none | project | `instructions-only` | `instructions-only` |
| `windsurf` | mcp-plus-instructions | `controlkeel attach windsurf` | none | project | `instructions-only` | `instructions-only` |
| `kiro` | mcp-plus-instructions | `controlkeel attach kiro` | none | project | `instructions-only` | `instructions-only` |
| `amp` | mcp-plus-instructions | `controlkeel attach amp` | none | project | `instructions-only` | `instructions-only` |
| `opencode` | mcp-plus-instructions | `controlkeel attach opencode` | none | project | `instructions-only` | `instructions-only` |
| `gemini-cli` | mcp-plus-instructions | `controlkeel attach gemini-cli` | none | project | `instructions-only` | `instructions-only` |
| `continue` | mcp-plus-instructions | `controlkeel attach continue` | none | project | `instructions-only` | `instructions-only` |
| `aider` | mcp-plus-instructions | `controlkeel attach aider` | none | project | `instructions-only` | `instructions-only` |

**Category meanings** (from `AgentIntegration.categories/0`):

- **native-first** — MCP registration plus native skills/agents on disk by default.
- **repo-native** — repo-scoped `.github` / `.vscode` skills and MCP config.
- **mcp-plus-instructions** — MCP server plus portable instruction bundles under `controlkeel/dist/instructions-only`.

The shipped `copilot` attach target is the repo-native path for GitHub Copilot, and the exported `copilot-plugin` bundle is the same companion path used for GitHub Copilot CLI and VS Code agent mode.

**Router agent IDs** (for `ck_route` / policy): where set in code, the integration’s `router_agent_id` matches the attach id (e.g. `opencode`, `cursor`); VS Code / Copilot use `nil` in the catalog.

## MCP runtime tools

Implemented under [`lib/controlkeel/mcp/tools/`](../lib/controlkeel/mcp/tools/). The MCP server advertises **five tools always**, and **adds** `ck_skill_list` and `ck_skill_load` when the runtime has a non-empty skill catalog (see `protocol.ex` `tool_schemas/0`).

| Tool | Purpose |
|------|---------|
| `ck_validate` | Run FastPath scan (patterns, Semgrep, optional LLM advisory); optional `session_id` / `task_id`; returns `advisory` metadata when present. |
| `ck_context` | Session/task context: findings summary, budget, memory hits, resume packet, provider status. Requires `session_id`. |
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

Names in research lists (see [idea/missing/check.md](../idea/missing/check.md)) do **not** automatically get catalog entries—each needs the above.
