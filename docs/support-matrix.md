# ControlKeel support matrix (canonical)

This document is the **single inventory** for attach targets, MCP tools, and bundled skills. It is maintained to match:

- [`lib/controlkeel/agent_integration.ex`](../lib/controlkeel/agent_integration.ex) — `AgentIntegration.catalog/0`
- [`lib/controlkeel/acp_registry.ex`](../lib/controlkeel/acp_registry.ex) — ACP registry enrichment and cache status
- [`lib/controlkeel/distribution.ex`](../lib/controlkeel/distribution.ex) — `required_mcp_tools/0`, install channels
- [`lib/controlkeel/mcp/protocol.ex`](../lib/controlkeel/mcp/protocol.ex) — tool schemas exposed to MCP clients
- [`lib/controlkeel/protocol_access.ex`](../lib/controlkeel/protocol_access.ex) — hosted MCP/A2A token flow and protocol scopes
- [`lib/controlkeel/protocol_interop.ex`](../lib/controlkeel/protocol_interop.ex) — hosted MCP/A2A dispatch wrappers
- [`priv/skills/`](../priv/skills/) — on-disk AgentSkills bundles

If you want the smaller user-facing docs map first, start with [README.md](README.md).

For install paths and proxy URLs, see [agent-integrations.md](agent-integrations.md), [getting-started.md](getting-started.md), [host-surface-parity.md](host-surface-parity.md), and [direct-host-installs.md](direct-host-installs.md).
Product intent and acceptance criteria for this matrix live in [agent-support-prd.md](agent-support-prd.md) and [agent-support-requirements.md](agent-support-requirements.md).

## Typed integration catalog (`AgentIntegration.catalog/0`)

Every shipped integration row now declares both a **support class** and a **two-way execution model**:

- `attach_client`
- `headless_runtime`
- `framework_adapter`
- `provider_only`
- `alias`
- `unverified`

Only `attach_client` rows produce real `controlkeel attach <id>` commands. `headless_runtime` rows export runtime bundles, `framework_adapter` rows surface through benchmark/policy tooling, `provider_only` rows surface through CK provider flows, and `alias` rows point at a canonical shipped target.

Every shipped row also carries the stricter parity contract exposed in `/skills` and `GET /api/v1/skills/targets`:

- `install_experience`
- `review_experience`
- `submission_mode`
- `feedback_mode`
- `plan_phase_support`
- `phase_model`
- `browser_embed`
- `subagent_visibility`
- `artifact_surfaces`
- `package_outputs`
- `direct_install_methods`
- `confidence_level`
- `runtime_transport`
- `runtime_auth_owner`
- `runtime_session_support`
- `runtime_review_transport`

Attachable and runtime integrations use the same governed MCP surface. Core routing/governance tools are always present, extended governance tools are currently enabled in protocol responses, and `ck_skill_list` / `ck_skill_load` are included when skills are available.

The MCP surface is intentionally discovery-friendly rather than "dump everything into context" by default:

- `tools/list` exposes the stable governed tool contract
- hosted MCP can further narrow that list to the scoped hosted subset
- skill catalogs and skill bodies are loaded separately through `ck_skill_list`, `ck_skill_load`, `resources/list`, `resources/read`, and `ck_load_resources`
- tool results return `structuredContent`, so clients can compose over stable machine-readable payloads instead of reparsing long natural-language responses

That design is important to the catalog itself. CK does not treat a large workspace skill inventory as a reason to bloat handshake-time context. It prefers progressive discovery and on-demand loading, especially in stdio MCP mode where slow registry walks can hurt connection reliability.

The intent layer now consumes this same catalog for runtime recommendation. In practice:

- approval-heavy or regulated briefs usually recommend an `attach_client` row with stronger review transport
- API-heavy briefs that look like code-mode or typed-runtime work can recommend a `headless_runtime` export such as `cloudflare-workers`
- the resulting recommendation is exposed through `ControlKeel.Intent.runtime_recommendation/1` and embedded in `boundary_summary`
- if CK can see attached agents through provider status, those attached hosts are preferred over equally good catalog-only options
- exported runtime bundles are treated as the strongest signal that a headless runtime path is already available in the workspace
- recommendation payloads now label availability as `attached`, `configured`, or `catalog`

For defensive-security sessions, CK layers additional behavior on top of the same catalog instead of inventing a separate host matrix:

- reproduction-phase work requires `verified_research` and isolated runtime execution
- disclosure artifacts default to redaction and proof references
- release readiness can block on unresolved critical vulnerability cases
- the dedicated behavior guide is [defensive-security-with-controlkeel.md](defensive-security-with-controlkeel.md)

## Host parity classes

These are the first-class host adapters that currently implement the richer review transport instead of a generic support claim:

| Host | Attach command | Phase model | Review experience | Browser embed | Subagent visibility | Declared package outputs |
| ---- | ---------------- | ------------- | ------------------- | --------------- | --------------------- | -------------------------- |
| `claude-code` | `controlkeel attach claude-code` | `host_plan_mode` | `native_review` via Claude hooks | `external` | `primary_only` | `controlkeel-claude-plugin.tar.gz` |
| `copilot` | `controlkeel attach copilot` | `host_plan_mode` | `native_review` via repo/plugin hooks | `external` | `primary_only` | `controlkeel-copilot-plugin.tar.gz` |
| `opencode` | `controlkeel attach opencode` | `host_plan_mode` | `native_review` via plugin tool call | `external` | `primary_only` | `controlkeel-opencode-native.tar.gz`, `controlkeel-opencode-native.tgz` |
| `augment` | `controlkeel attach augment` | `host_plan_mode` | `native_review` via Auggie plugin hooks and command loop | `external` | `all` | `controlkeel-augment-native.tar.gz`, `controlkeel-augment-plugin.tar.gz` |
| `pi` | `controlkeel attach pi` | `file_plan_mode` | `browser_review` with persisted plan file state | `external` | `primary_only` | `controlkeel-pi-native.tar.gz`, `controlkeel-pi-native.tgz` |
| `vscode` | `controlkeel attach vscode` | `review_only` | `browser_review` through companion extension | `vscode_webview` | `none` | `controlkeel-github-repo.tar.gz`, `controlkeel-vscode-companion.vsix` |
| `codex-cli` | `controlkeel attach codex-cli` | `review_only` | `browser_review` through native commands | `none` | `primary_only` | `controlkeel-codex.tar.gz`, `controlkeel-codex-plugin.tar.gz` |

Everything else in the catalog remains supported according to its own typed row, but is not marketed as a first-class host adapter unless it has a real install surface plus a defined review path.

For OpenCode specifically, CK now installs native `.opencode/skills` alongside `.agents/skills` compatibility copies so governed skills load through OpenCode-native and AgentSkills-compatible discovery paths.

For Codex specifically, CK now installs native `.codex/skills` and repo-scoped `.codex/hooks` alongside `.agents/skills` compatibility copies so the governed skill set works in the current Codex home/project model without dropping the open-standard AgentSkills path.

Use [direct-host-installs.md](direct-host-installs.md) for the exact companion package names, install commands, and current package-manager truth.

For the broader `skills.sh` agent list, CK currently splits support into:

- canonical native targets already in this matrix
- alias rows that normalize naming differences such as `codex`, `gemini`, `kiro-cli`, and `roo`
- skills-compatible-only research rows such as `antigravity`, `clawdbot`, `nous-research`, and `trae`, which currently resolve to open-standard AgentSkills installs rather than a native attach command

The broader native matrix now also tracks the strongest official surfaces CK exports for each host:

| Host | Strongest shipped official surface |
| ---- | ---------------------------------- |
| `windsurf` | Cascade hooks, workflows, commands, and MCP config |
| `continue` | prompts, command prompts, headless guidance, and `.continue/mcpServers/controlkeel.yaml` |
| `letta-code` | `.agents/skills`, `.letta/settings.json` hooks, `.letta/controlkeel-mcp.sh`, `.letta/README.md`, and portable `.mcp.json` guidance |
| `cline` | rules, workflows, commands, hook scripts, and CLI MCP config |
| `goose` | repo hints, workflow recipes, commands, and Goose extension YAML |
| `kiro` | hooks, steering, tool-policy settings, commands, and MCP config |
| `kilo` | Agent Skills, slash-command workflows, `.kilo/kilo.json`, and `AGENTS.md` |
| `amp` | TypeScript plugin, native skill bundle, custom tool/command surface, and package scaffold |
| `augment` | workspace commands, subagents, rules, MCP config, local plugin hooks, and ACP-compatible runtime metadata |
| `gemini-cli` | extension manifest, review/submit-plan commands, and skill bundle |
| `cursor` | rules, Agent Skills (`.cursor/skills`), slash commands, governed agent prompts, background-agent guidance, repo `hooks.json` + hook scripts, MCP config, and `.cursor-plugin/` bundle |
| `roo-code` | rules, commands, governed modes, and cloud-agent guidance |
| `aider` | command-driven snippets, `.aider.conf.yml`, and `AIDER.md` |

For command-capable hosts, CK now standardizes the agent-facing governance loop as much as the host format allows:

- `review`
- `submit-plan`
- `annotate`
- `last`

For hosts with a stronger native capability container, CK now prefers that too instead of forcing humans to reconstruct the flow:

- Windsurf ships a canonical `.windsurf/hooks.json` workspace hook config in addition to the portable hook assets.
- Amp ships a native `controlkeel-governance` skill bundle with MCP wiring in addition to the plugin and command layer.
- Augment ships a repo-native `.augment/` workspace bundle plus a local `.augment-plugin` hook bundle, so CK can be used by the agent through either workspace commands or hook-native interception.

This keeps the product aligned with CK’s intent: agents should be able to invoke ControlKeel directly during autonomous work, rather than depending on the human operator to manually drive review state transitions.

Runtime transport truth for those first-class hosts:

| Host | Runtime transport | Runtime auth owner | Runtime review transport | Session support |
| ---- | ----------------- | ------------------ | ------------------------ | --------------- |
| `claude-code` | `claude_agent_sdk` | `agent` | `hook_sdk` | create, fork, resume, streaming |
| `copilot` | `hook_session_parser` | `agent` | `hook_session_state` | no CK-owned session lifecycle claims |
| `opencode` | `opencode_sdk` | `agent` | `plugin_session_tool` | create, fork, resume, streaming |
| `augment` | `auggie_sdk_acp` | `agent` | `plugin_hook_acp` | create, resume, streaming; no fork claims |
| `pi` | `pi_rpc` | `agent` | `extension_rpc` | create and streaming; no fork claims |
| `vscode` | `vscode_companion` | `workspace` | `vscode_ipc` | none |
| `codex-cli` | `codex_sdk` | `agent` | `command_thread` | create, resume, streaming; no fork claims |

| ID | Support class | Action | Agent uses CK via | CK runs agent via | Execution support | Auth / skills | Preferred export / bundle |
| ---- | --------------- | -------- | ------------------- | ------------------- | ------------------ | --------------- | --------------------------- |
| `claude-code` | attach_client | `controlkeel attach claude-code` | `local_mcp`, `plugin`, `native_skills` | `embedded` | `direct` | `env_bridge` / `native` | `claude-standalone` |
| `codex-cli` | attach_client | `controlkeel attach codex-cli` | `local_mcp`, `plugin`, `native_skills` | `embedded` | `direct` | `agent_runtime` / `native` | `codex` |
| `cline` | attach_client | `controlkeel attach cline` | `local_mcp`, `native_skills`, `rules`, `workflows`, `hooks`, `commands` | `embedded` | `direct` | `ck_owned` / `native` | `cline-native` |
| `roo-code` | attach_client | `controlkeel attach roo-code` | `local_mcp`, `native_skills`, `rules`, `workflows`, `commands` | `handoff` | `handoff` | `ck_owned` / `native` | `roo-native` |
| `goose` | attach_client | `controlkeel attach goose` | `local_mcp`, `workflows`, `hooks`, `commands` | `handoff` | `handoff` | `ck_owned` / `native` | `goose-native` |
| `vscode` | attach_client | `controlkeel attach vscode` | `local_mcp`, `plugin`, `native_skills`, `workflows`, `hooks` | `handoff` | `handoff` | `ck_owned` / `native` | `github-repo` |
| `copilot` | attach_client | `controlkeel attach copilot` | `local_mcp`, `plugin`, `native_skills`, `workflows`, `hooks` | `embedded` | `direct` | `agent_runtime` / `native` | `github-repo` |
| `cursor` | attach_client | `controlkeel attach cursor` | `local_mcp`, `native_skills`, `rules`, `commands`, `workflows`, `hooks`, `plugin` | `handoff` | `handoff` | `ck_owned` / `native` | `cursor-native` |
| `windsurf` | attach_client | `controlkeel attach windsurf` | `local_mcp`, `native_skills`, `rules`, `hooks`, `workflows`, `commands` | `handoff` | `handoff` | `ck_owned` / `native` | `windsurf-native` |
| `kiro` | attach_client | `controlkeel attach kiro` | `local_mcp`, `native_skills`, `hooks`, `rules`, `commands` | `handoff` | `handoff` | `ck_owned` / `native` | `kiro-native` |
| `amp` | attach_client | `controlkeel attach amp` | `local_mcp`, `plugin`, `native_skills`, `commands`, `tool_call` | `handoff` | `handoff` | `ck_owned` / `native` | `amp-native` |
| `augment` | attach_client | `controlkeel attach augment` | `local_mcp`, `plugin`, `native_skills`, `rules`, `commands`, `hooks` | `embedded` | `direct` | `agent_runtime` / `native` | `augment-native` |
| `opencode` | attach_client | `controlkeel attach opencode` | `local_mcp`, `plugin`, `native_skills`, `rules`, `commands` | `embedded` | `direct` | `agent_runtime` / `native` | `opencode-native` |
| `gemini-cli` | attach_client | `controlkeel attach gemini-cli` | `local_mcp`, `native_skills`, `rules`, `commands` | `embedded` | `direct` | `ck_owned` / `native` | `gemini-cli-native` |
| `continue` | attach_client | `controlkeel attach continue` | `local_mcp`, `native_skills`, `rules`, `workflows`, `commands` | `embedded` | `direct` | `ck_owned` / `native` | `continue-native` |
| `letta-code` | attach_client | `controlkeel attach letta-code` | `local_mcp`, `native_skills`, `hooks` | `embedded` | `direct` | `ck_owned` / `native` | `letta-code-native` |
| `kilo` | attach_client | `controlkeel attach kilo` | `local_mcp`, `native_skills`, `commands` | `embedded` | `direct` | `ck_owned` / `native` | `kilo-native` |
| `pi` | attach_client | `controlkeel attach pi` | `local_mcp`, `native_skills`, `commands`, `rules` | `handoff` | `handoff` | `agent_runtime` / `native` | `pi-native` |
| `aider` | attach_client | `controlkeel attach aider` | `local_mcp`, `commands` | `embedded` | `direct` | `ck_owned` / `instructions_only` | `instructions-only` |
| `hermes-agent` | attach_client | `controlkeel attach hermes-agent` | `local_mcp`, `plugin`, `native_skills` | `handoff` | `handoff` | `config_reference` / `native` | `hermes-native` |
| `openclaw` | attach_client | `controlkeel attach openclaw` | `local_mcp`, `plugin`, `native_skills` | `handoff` | `handoff` | `config_reference` / `plugin_bundle` | `openclaw-native` |
| `droid` | attach_client | `controlkeel attach droid` | `local_mcp`, `native_skills`, `commands`, `plugin` | `handoff` | `handoff` | `gateway_base_url` / `native` | `droid-bundle`, `droid-plugin` |
| `forge` | attach_client | `controlkeel attach forge` | `hosted_mcp`, `a2a` | `runtime` | `runtime` | `acp_session` / `instructions_only` | `forge-acp` |
| `devin` | headless_runtime | `controlkeel runtime export devin` | `hosted_mcp`, `a2a` | `runtime` | `runtime` | `oauth_runtime` / `instructions_only` | `devin-runtime` |
| `open-swe` | headless_runtime | `controlkeel runtime export open-swe` | `hosted_mcp`, `a2a` | `runtime` | `runtime` | `ck_owned` / `instructions_only` | `open-swe-runtime` |
| `executor` | headless_runtime | `controlkeel runtime export executor` | `hosted_mcp`, `a2a` | `runtime` | `runtime` | `oauth_runtime` / `instructions_only` | `executor-runtime` |
| `virtual-bash` | headless_runtime | `controlkeel runtime export virtual-bash` | `hosted_mcp`, `commands` | `runtime` | `runtime` | `ck_owned` / `instructions_only` | `virtual-bash-runtime` |
| `dspy` | framework_adapter | adapter only | none | `none` | `inbound_only` | `ck_owned` / `none` | `framework-adapter` |
| `gepa` | framework_adapter | adapter only | none | `none` | `inbound_only` | `ck_owned` / `none` | `framework-adapter` |
| `deepagents` | framework_adapter | adapter only | none | `none` | `inbound_only` | `ck_owned` / `none` | `framework-adapter` |
| `fastmcp` | framework_adapter | adapter only | none | `none` | `inbound_only` | `none` / `none` | `framework-adapter` |
| `conductor` | framework_adapter | use Claude Code repo-local surfaces inside Conductor | `local_mcp`, `native_skills`, `commands` | `none` | `inbound_only` | `heuristic` / `native` | `claude-standalone`, `claude-plugin`, `instructions-only` |
| `paperclip` | framework_adapter | use CK-native attach surfaces inside Paperclip agent adapters | `local_mcp`, `native_skills`, `commands`, `plugin` | `none` | `inbound_only` | `config_reference` / `native` | `framework-adapter` |
| `augment-intent` | framework_adapter | adapter only | none | `none` | `inbound_only` | `none` / `none` | `framework-adapter` |
| `codestral` | provider_only | provider template only | none | `none` | `inbound_only` | `ck_owned` / `none` | `provider-profile` |
| `ollama-runtime` | provider_only | provider template only | none | `none` | `inbound_only` | `local` / `none` | `provider-profile` |
| `vllm` | provider_only | provider template only | none | `none` | `inbound_only` | `ck_owned` / `none` | `provider-profile` |
| `sglang` | provider_only | provider template only | none | `none` | `inbound_only` | `ck_owned` / `none` | `provider-profile` |
| `lmstudio` | provider_only | provider template only | none | `none` | `inbound_only` | `ck_owned` / `none` | `provider-profile` |
| `huggingface` | provider_only | provider template only | none | `none` | `inbound_only` | `ck_owned` / `none` | `provider-profile` |
| `claude-dispatch` | alias | use `claude-code` | same as `claude-code` | `embedded` | `direct` | `env_bridge` / `native` | `claude-standalone` |
| `cognition` | alias | use `devin` | same as `devin` | `runtime` | `runtime` | `oauth_runtime` / `instructions_only` | `devin-runtime` |
| `codex-app-server` | attach client | `controlkeel attach codex-cli` | same `.codex/*` local surface as `codex-cli`, but tracked as a dedicated app-server runtime | `embedded` | `direct` | `agent_runtime` / `native` | `codex` |
| `cursor-agent` | alias | use `cursor` | same as `cursor` | `handoff` | `handoff` | `ck_owned` / `native` | `cursor-native` |
| `copilot-cli` | alias | use `copilot` | same as `copilot` | `embedded` | `direct` | `ck_owned` / `native` | `github-repo` |
| `copilot-web` | alias | use `copilot` | same as `copilot` | `embedded` | `direct` | `ck_owned` / `native` | `github-repo` |
| `cursor-web` | alias | use `cursor` | same as `cursor` | `handoff` | `handoff` | `ck_owned` / `native` | `cursor-native` |
| `conductor-web` | alias | use `conductor` | same as `conductor` | `none` | `inbound_only` | `heuristic` / `native` | `claude-standalone`, `claude-plugin`, `instructions-only` |
| `augment-cli` | alias | use `augment` | same as `augment` | `embedded` | `direct` | `agent_runtime` / `native` | `augment-native` |
| `auggie-cli` | alias | use `augment` | same as `augment` | `embedded` | `direct` | `agent_runtime` / `native` | `augment-native` |
| `kimi-cli` | alias | use `codex-cli` | same as `codex-cli` | `embedded` | `direct` | `agent_runtime` / `native` | `codex` |
| `t3code` | alias | use `codex-cli` | same as `codex-cli` | `embedded` | `direct` | `agent_runtime` / `native` | `codex` |
| `rlm-agent` | unverified | research only | none | `none` | `inbound_only` | `none` / `none` | n/a |
| `slate` | unverified | research only | none | `none` | `inbound_only` | `none` / `none` | n/a |
| `retune` | unverified | research only | none | `none` | `inbound_only` | `none` / `none` | n/a |
| `claw-code` | unverified | research only (community leak-era port) | none | `none` | `inbound_only` | `none` / `none` | n/a |
| `claude-code-source-mirror` | unverified | research only (leak-derived mirror) | none | `none` | `inbound_only` | `none` / `none` | n/a |
| `z-ai-cli` | unverified | research only (evolving ecosystem) | none | `none` | `inbound_only` | `none` / `none` | n/a |
| `capydotai` | unverified | research only | none | `none` | `inbound_only` | `none` / `none` | n/a |
| `neosigma` | unverified | research only | none | `none` | `inbound_only` | `none` / `none` | n/a |

The shipped `copilot` attach target is the repo-native path for GitHub Copilot, and the exported `copilot-plugin` bundle is the same companion path used for GitHub Copilot CLI and VS Code agent mode.

All shipped attach/runtime rows currently use `policy_gated` autonomy. `/skills` and `GET /api/v1/skills/targets` expose the exact code-backed values as `agent_uses_ck_via`, `ck_runs_agent_via`, `execution_support`, and `autonomy_mode`.

Provider-only backends such as `vllm`, `sglang`, `lmstudio`, `huggingface`, and `codestral` currently flow through the CK `openai` provider path with a custom `base_url` and `model`; they are cataloged separately so the support matrix stays honest about the backend you are really targeting.

**Router agent IDs** (for `ck_route` / policy): where set in code, the integration’s `router_agent_id` matches the attach id (e.g. `opencode`, `cursor`); VS Code / Copilot use `nil` in the catalog.

## ACP registry enrichment

The typed integration catalog stays authoritative. ACP registry data is **supplemental only**.

Registry support in the product currently means:

- `controlkeel registry sync acp`
- `controlkeel registry status acp`
- `/skills` shows cache freshness and per-row registry hints
- `GET /api/v1/skills/targets` returns optional fields:
  - `registry_match`
  - `registry_id`
  - `registry_version`
  - `registry_url`
  - `registry_stale`
- the same API payload includes top-level `registry_status`

Registry data never creates new attach targets and never mutates shipped install behavior.

## Hosted protocol interop

ControlKeel now exposes both local stdio MCP and hosted interop surfaces.

### Local stdio MCP

- entrypoint: `controlkeel mcp --project-root /abs/path`
- auth model: local trust
- intended use: repo-local native attach flows

### Hosted MCP

- entrypoint: `POST /mcp`
- discovery:
  - `GET /.well-known/oauth-protected-resource/mcp`
  - `GET /.well-known/oauth-protected-resource`
  - `GET /.well-known/oauth-authorization-server`
- token exchange: `POST /oauth/token`
- auth model: short-lived bearer tokens minted from workspace service accounts
- transport model: stateless JSON-response mode only

Hosted MCP tool authorization uses these protocol scopes:

| Tool | Required scopes |
| ------ | ----------------- |
| `ck_context` | `mcp:access`, `context:read` |
| `ck_validate` | `mcp:access`, `validate:run` |
| `ck_finding` | `mcp:access`, `finding:write` |
| `ck_review_submit` | `mcp:access`, `review:write` |
| `ck_review_status` | `mcp:access`, `review:read` |
| `ck_review_feedback` | `mcp:access`, `review:respond` |
| `ck_context`, `ck_experience_index`, `ck_experience_read`, `ck_trace_packet`, `ck_failure_clusters`, `ck_skill_evolution`, `ck_fs_ls`, `ck_fs_read`, `ck_fs_find`, `ck_fs_grep` | `mcp:access`, `context:read` |
| `ck_regression_result` | `mcp:access`, `regression:write` |
| `ck_memory_search` | `mcp:access`, `memory:read` |
| `ck_memory_record`, `ck_memory_archive` | `mcp:access`, `memory:write` |
| `ck_budget` | `mcp:access`, `budget:write` |
| `ck_route` | `mcp:access`, `route:read` |
| `ck_delegate` | `mcp:access`, `delegate:run` |
| `ck_cost_optimizer` | `mcp:access`, `cost:read` |
| `ck_outcome_tracker` | `mcp:access`, `outcome:read`, `outcome:write` |
| `ck_skill_list`, `ck_skill_load` | `mcp:access`, `skills:read` |

`ck_deployment_advisor` is intentionally not exposed through hosted MCP yet because its current contract operates on an arbitrary `project_root` path rather than a session-bound workspace root.

Service-account responses in the CLI and `/api/v1/workspaces/:id/service-accounts` include the derived `oauth_client_id` for this flow.

### Minimal A2A

- discovery:
  - `GET /.well-known/agent-card.json`
  - `GET /.well-known/agent.json`
- invoke: `POST /a2a`
- auth model: same service-account bearer flow, using `a2a:access`
- supported method: `message/send` only

Advertised A2A skills map directly to the core governed capabilities:

- `ck_context`
- `ck_validate`
- `ck_finding`
- `ck_review_submit`
- `ck_review_status`
- `ck_review_feedback`
- `ck_budget`
- `ck_route`
- `ck_delegate`

## Governed agent execution

Bidirectional execution surfaces in the product now include:

- `controlkeel agents doctor`
- `controlkeel run task <id> [--agent auto|<id>] [--mode auto|embedded|handoff|runtime]`
- `controlkeel run session <id> [--agent auto|<id>]`
- `GET /api/v1/agents`
- `POST /api/v1/tasks/:id/run`
- `POST /api/v1/sessions/:id/run`

These reuse the existing task-run, findings, proofs, and policy-gate primitives rather than inventing a second execution model.

CK now makes the execution posture explicit in the brief and context layer:

- `virtual_workspace` is the default read path for discovery (`ck_fs_ls`, `ck_fs_read`, `ck_fs_find`, `ck_fs_grep`)
- `typed_storage` is the durable state path for proofs, memory, traces, and outcome tracking
- `typed_runtime` is the preferred path for large API or MCP-style tool surfaces when the host can offer code-mode execution
- `shell_sandbox` remains the broad fallback path for repo mutation, package management, and test execution, with the strongest approval pressure

## MCP runtime tools

Implemented under [`lib/controlkeel/mcp/tools/`](../lib/controlkeel/mcp/tools/). The MCP server advertises the core and extended governance tools, and adds `ck_skill_list` and `ck_skill_load` when the runtime has a non-empty skill catalog (see `protocol.ex` `tool_schemas/0`).

| Tool | Purpose |
| ------ | --------- |
| `ck_validate` | Run FastPath scan (patterns, destructive shell tripwires, Semgrep, optional LLM advisory); optional `session_id` / `task_id`; returns `advisory` metadata when present plus recovery guidance for destructive shell findings. |
| `ck_context` | Session/task context: findings summary, budget, production boundary summary, memory hits, proof summary, workspace snapshot, workspace cache key, reacquisition signals, design-drift summary, recent transcript events, transcript summary, resume packet, and provider status. Requires `session_id`; accepts optional `project_root`, but governed runtime context wins when CK already knows the workspace root. |
| `ck_experience_index` | List recent prior sessions in the same workspace plus the read-only experience artifacts available for each run. |
| `ck_experience_read` | Read one prior-run artifact such as a session summary, audit log, trace packet, or proof summary. |
| `ck_trace_packet` | Export a structured session or task trace packet with failure patterns and eval candidates so teams can turn real runs into reusable improvement cases. |
| `ck_failure_clusters` | Cluster recurring failure modes across recent workspace traces and return reusable eval candidates for the highest-frequency patterns. |
| `ck_skill_evolution` | Synthesize one deduplicated skill-evolution packet from recent traces and failure clusters, including anti-patterns, reinforced practices, merged Do/Avoid/Verification guidance, and a ready-to-merge skill draft. |
| `ck_fs_ls` | List files and directories inside the bound project root through a read-only virtual workspace surface. |
| `ck_fs_read` | Read a text file from the bound project root without provisioning a sandbox. |
| `ck_fs_find` | Find files or directories by path fragment inside the bound project root. |
| `ck_fs_grep` | Search file contents inside the bound project root with grep-style semantics over the read-only virtual workspace. |
| `ck_finding` | Record a governed finding for a session (and optional task). |
| `ck_review_submit` | Submit a plan, diff, or completion packet for browser review and execution gating. |
| `ck_review_status` | Fetch latest review status, notes, and browser URL by `review_id` or `task_id`. |
| `ck_review_feedback` | Approve or deny a submitted review and persist feedback notes or annotations. |
| `ck_regression_result` | Record external regression-test evidence from systems like Bug0 or Passmark so proof bundles and release readiness can account for browser/UI failures. |
| `ck_memory_search` | Search typed memory explicitly for prior decisions, findings, proofs, and checkpoints within the current session scope. |
| `ck_memory_record` | Persist an explicit memory note or decision for later agent retrieval. |
| `ck_memory_archive` | Archive a stale or superseded memory record so it stops surfacing in retrieval. |
| `ck_budget` | Budget estimate or commit (`mode`: `estimate` \| `commit`). |
| `ck_route` | Agent routing recommendation from `AgentRouter` (`task`, optional `risk_tier`, `budget_remaining_cents`, `allowed_agents`). |
| `ck_delegate` | Ask ControlKeel to run or hand off another agent for a task or session under the current policy gates. |
| `ck_cost_optimizer` | Recommend spend reductions and lower-cost agent/model alternatives for current work context. |
| `ck_deployment_advisor` | Analyze deployment posture and return stack-aware deployment guidance. Local/stdio MCP only for now; not advertised on hosted MCP. |
| `ck_outcome_tracker` | Record or query execution outcomes used for quality and routing feedback loops. |
| `ck_skill_list` | List AgentSkills from the registry (optional `project_root`, `target`, `format`). **Only registered when skills exist.** |
| `ck_skill_load` | Load `SKILL.md` for a named skill with optional target-family rendering. **Only registered when skills exist.** |

Authoritative tool names in code are split between `ControlKeel.Distribution.required_mcp_tools/0` (core required set) and `ControlKeel.Mcp.Protocol.tool_schemas/0` (advertised runtime surface, including extended governance tools).

## Bundled skills (`priv/skills/`)

These directories ship with the repo and are discovered by [`ControlKeel.Skills.Registry`](../lib/controlkeel/skills/registry.ex):

| Skill directory | Role |
| ----------------- | ------ |
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
