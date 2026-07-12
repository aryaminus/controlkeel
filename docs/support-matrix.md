# ControlKeel support matrix (canonical)

This document is the **single inventory** for attach targets, MCP tools, and bundled skills. It is maintained to match:

- [`lib/controlkeel/agent/integration.ex`](../lib/controlkeel/agent/integration.ex) — `Agent.Integration.catalog/0`
- [`lib/controlkeel/agent/acp_registry.ex`](../lib/controlkeel/agent/acp_registry.ex) — ACP registry enrichment and cache status
- [`lib/controlkeel/ops/distribution.ex`](../lib/controlkeel/ops/distribution.ex) — `required_mcp_tools/0`, install channels
- [`lib/controlkeel/mcp/protocol.ex`](../lib/controlkeel/mcp/protocol.ex) — tool schemas exposed to MCP clients
- [`lib/controlkeel/mcp/protocol_access.ex`](../lib/controlkeel/mcp/protocol_access.ex) — hosted MCP/A2A token flow and protocol scopes
- [`lib/controlkeel/mcp/protocol_interop.ex`](../lib/controlkeel/mcp/protocol_interop.ex) — hosted MCP/A2A dispatch wrappers
- [`priv/skills/`](../priv/skills/) — on-disk AgentSkills bundles

If you want the smaller user-facing docs map first, start with [README.md](README.md).

For install paths and proxy URLs, see [agent-integrations.md](agent-integrations.md), [getting-started.md](getting-started.md), and [packages.md](packages.md).

## Typed integration catalog (`Agent.Integration.catalog/0`)

Every shipped integration row now declares both a **support class** and a **two-way execution model**:

- `attach_client`
- `headless_runtime`
- `framework_adapter`
- `alias`
- `unverified`

Only `attach_client` rows produce real `controlkeel attach <id>` commands. `headless_runtime` rows export runtime bundles, `framework_adapter` rows remain only where they point at a concrete CK export/underlying surface, and `alias` rows point at a canonical shipped target.

Every shipped row also carries the stricter parity contract exposed in `/skills` and `GET /api/v1/skills/targets`:

The API also exposes a coarse `experience_profile` map for balancing host choice without pretending CK can know account-specific subscription state. The profile tracks `cost`, `performance`, `token_pressure`, `time`, and `ux` with stable labels such as `host_subscription_or_agent_metered`, `ck_budget_metered`, `interactive_direct`, `background_runtime`, `host_quota_sensitive`, `fast_feedback`, and `native_governed`. Use these labels as guidance alongside real budget/rate-limit telemetry, not as hard quota claims.

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

For defensive-security sessions, CK layers additional behavior on top of the same catalog instead of inventing a separate host matrix:

- reproduction-phase work requires `verified_research` and isolated runtime execution
- disclosure artifacts default to redaction and proof references
- release readiness can block on unresolved critical vulnerability cases
- use the `security` domain pack and [autonomy-and-findings.md](autonomy-and-findings.md) for release-blocking behavior

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
| `warp` | `controlkeel attach warp` | `host_plan_mode` | `native_review` through Warp local agent review and MCP tool calls | `external` | `all` | `controlkeel-warp-native.tar.gz` |
| `devin-terminal` | `controlkeel attach devin-terminal` | `host_plan_mode` | `native_review` via Claude-compatible Devin hooks and MCP tool calls | `external` | `all` | `controlkeel-devin-terminal-native.tar.gz` |

Everything else in the catalog remains supported according to its own typed row, but is not marketed as a first-class host adapter unless it has a real install surface plus a defined review path.

For OpenCode specifically, CK now installs native `.opencode/skills` alongside `.agents/skills` compatibility copies so governed skills load through OpenCode-native and AgentSkills-compatible discovery paths.

For Codex specifically, CK now installs native `.codex/skills` and repo-scoped `.codex/hooks` alongside `.agents/skills` compatibility copies so the governed skill set works in the current Codex home/project model without dropping the open-standard AgentSkills path.

Use [packages.md](packages.md) for package names, install commands, and current package-manager truth.

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
| `amp` | Amp Neo TypeScript Plugin API permission hooks, native skill bundle, custom tool/command surface, queue/steer-aware commands, and package scaffold |
| `augment` | workspace commands, subagents, rules, MCP config, local plugin hooks, and ACP-compatible runtime metadata |
| `warp` | `.warp/skills`, `.agents/skills`, `.warp/controlkeel-mcp.json`, `.warp/README.md`, and `AGENTS.md` |
| `devin-terminal` | `.devin/config.json`, `.devin/hooks.v1.json`, `.devin/hooks`, `.devin/skills`, `.devin/agents`, `.agents/skills`, and `AGENTS.md` |
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
- Amp Neo is remote-controllable from ampcode.com, auto-compacts long threads, and queues/steers operator messages; CK models those as host capabilities while keeping durable proof/memory in CK.
- **Queue/steer semantics**: Amp Neo defaults to queued messages (wait until agent idle), which CK treats as the preferred predictable mode for governed work. **Steer** fast-tracks a queued message to the next tool-result boundary; CK models this as a stronger operator intervention that should carry audit metadata (who steered, when, what message). **Interrupt** (Esc Esc) sends immediately and stops current agent work; CK treats this as the highest-authority operator event, comparable to a human stopping a running task, and records it as a governance checkpoint.
- **Compaction provenance**: Amp Neo auto-compacts at 90% context fill using its own harness, not the model provider's native context management. CK tracks compaction source as `host_harness`, `provider_native`, or `ck_resume_packet` for proof/memory trust and audit trails. Host-harness compaction is visible to the host but opaque to CK's typed storage; ck_resume_packet preserves full provenance.
- **Remote control and CK-gated execution**: Amp removed manual bash invocation ($/$$) partly due to destructive-command risk. CK's stance is reinforced: no manual remote bash affordance by default. If remote-control commands need shell execution, they must go through CK-gated tool calls (ck_validate, ck_review_submit), not raw remote shell. Remote-control messages are treated as operator inputs with the same governance semantics as any other human intervention.
- Amp ships a native `controlkeel-governance` skill bundle with MCP wiring in addition to the Plugin API permission hook and command layer. CK does not treat Amp's no-prompt default as a governed permission policy; CK validation and findings remain the policy gate.
- Augment ships a repo-native `.augment/` workspace bundle plus a local `.augment-plugin` hook bundle, so CK can be used by the agent through either workspace commands or hook-native interception.

This keeps the product aligned with CK’s intent: agents should be able to invoke ControlKeel directly during autonomous work, rather than depending on the human operator to manually drive review state transitions.

Experience profile cases for first-class hosts:

| Host | Cost | Performance | Token pressure | Time | UX |
| ---- | ---- | ----------- | -------------- | ---- | -- |
| `claude-code` | host subscription / agent metered | interactive direct | host quota sensitive | fast feedback | native governed |
| `opencode` | host subscription / agent metered | interactive direct | host quota sensitive | fast feedback | native governed |
| `cursor` | CK-budget metered by default | human handoff | CK budget sensitive | checkpoint driven | native governed |
| `vscode` | workspace subscription | human handoff | workspace quota sensitive | checkpoint driven | browser review |
| `devin` | host subscription / agent metered | background runtime | host quota sensitive | long-running OK | runtime export |

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
| `vscode` | attach_client | `controlkeel attach vscode` | `local_mcp`, `plugin`, `native_skills`, `workflows`, `hooks`, `commands` | `handoff` | `handoff` | `ck_owned` / `native` | `github-repo` |
| `copilot` | attach_client | `controlkeel attach copilot` | `local_mcp`, `plugin`, `native_skills`, `workflows`, `hooks`, `commands` | `embedded` | `direct` | `agent_runtime` / `native` | `github-repo` |
| `pi` | attach_client | `controlkeel attach pi` | `local_mcp`, `native_skills`, `commands`, `rules` | `handoff` | `handoff` | `agent_runtime` / `native` | `pi-native` |
| `cursor` | attach_client | `controlkeel attach cursor` | `local_mcp`, `native_skills`, `rules`, `commands`, `workflows`, `hooks`, `plugin` | `handoff` | `handoff` | `ck_owned` / `native` | `cursor-native` |
| `windsurf` | attach_client | `controlkeel attach windsurf` | `local_mcp`, `native_skills`, `rules`, `commands`, `workflows`, `hooks` | `handoff` | `handoff` | `ck_owned` / `native` | `windsurf-native` |
| `kiro` | attach_client | `controlkeel attach kiro` | `local_mcp`, `native_skills`, `hooks`, `rules`, `commands` | `handoff` | `handoff` | `ck_owned` / `native` | `kiro-native` |
| `kilo` | attach_client | `controlkeel attach kilo` | `local_mcp` | `none` | `inbound_only` | `ck_owned` / `native` | `kilo-native` |
| `amp` | attach_client | `controlkeel attach amp` | `local_mcp`, `plugin`, `native_skills`, `commands`, `tool_call`, `remote_control`, `queue_steer`, `auto_compaction` | `handoff` | `handoff` | `ck_owned` / `native` | `amp-native` |
| `augment` | attach_client | `controlkeel attach augment` | `local_mcp`, `plugin`, `native_skills`, `rules`, `commands`, `hooks` | `embedded` | `direct` | `agent_runtime` / `native` | `augment-native` |
| `opencode` | attach_client | `controlkeel attach opencode` | `local_mcp`, `plugin`, `native_skills`, `rules`, `commands` | `embedded` | `direct` | `agent_runtime` / `native` | `opencode-native` |
| `gemini-cli` | attach_client | `controlkeel attach gemini-cli` | `local_mcp`, `native_skills`, `rules`, `commands` | `embedded` | `direct` | `ck_owned` / `native` | `gemini-cli-native` |
| `continue` | attach_client | `controlkeel attach continue` | `local_mcp`, `native_skills`, `rules`, `workflows`, `commands` | `embedded` | `direct` | `ck_owned` / `native` | `continue-native` |
| `letta-code` | attach_client | `controlkeel attach letta-code` | `local_mcp`, `native_skills`, `hooks` | `embedded` | `direct` | `ck_owned` / `native` | `letta-code-native` |
| `aider` | attach_client | `controlkeel attach aider` | `local_mcp`, `commands` | `embedded` | `direct` | `ck_owned` / `instructions_only` | `instructions-only` |
| `cline` | attach_client | `controlkeel attach cline` | `local_mcp`, `native_skills`, `rules`, `workflows`, `commands` | `embedded` | `direct` | `ck_owned` / `native` | `cline-native` |
| `roo-code` | attach_client | `controlkeel attach roo-code` | `local_mcp`, `native_skills`, `rules`, `workflows`, `commands` | `handoff` | `handoff` | `ck_owned` / `native` | `roo-native` |
| `goose` | attach_client | `controlkeel attach goose` | `local_mcp`, `workflows`, `hooks`, `commands` | `handoff` | `handoff` | `ck_owned` / `native` | `goose-native` |
| `hermes-agent` | attach_client | `controlkeel attach hermes-agent` | `local_mcp`, `plugin`, `native_skills` | `handoff` | `handoff` | `config_reference` / `native` | `hermes-native` |
| `openclaw` | attach_client | `controlkeel attach openclaw` | `local_mcp`, `plugin`, `native_skills` | `handoff` | `handoff` | `config_reference` / `plugin_bundle` | `openclaw-native` |
| `droid` | attach_client | `controlkeel attach droid` | `local_mcp`, `native_skills`, `commands`, `plugin` | `handoff` | `handoff` | `gateway_base_url` / `native` | `droid-bundle` |
| `forge` | attach_client | `controlkeel attach forge` | `hosted_mcp`, `a2a` | `runtime` | `runtime` | `acp_session` / `instructions_only` | `forge-acp` |
| `warp` | attach_client | `controlkeel attach warp` | `local_mcp`, `native_skills`, `rules` | `embedded` | `direct` | `agent_runtime` / `native` | `warp-native` |
| `warp-oz` | headless_runtime | `controlkeel runtime export warp-oz` | `hosted_mcp`, `native_skills`, `rules` | `runtime` | `runtime` | `oauth_runtime` / `instructions_only` | `warp-oz-runtime` |
| `devin` | headless_runtime | `controlkeel runtime export devin` | `hosted_mcp`, `a2a` | `runtime` | `runtime` | `oauth_runtime` / `instructions_only` | `devin-runtime` |
| `devin-terminal` | attach_client | `controlkeel attach devin-terminal` | `local_mcp`, `native_skills`, `rules`, `hooks` | `embedded` | `direct` | `agent_runtime` / `native` | `devin-terminal-native` |
| `open-swe` | headless_runtime | `controlkeel runtime export open-swe` | `hosted_mcp`, `a2a` | `runtime` | `runtime` | `ck_owned` / `instructions_only` | `open-swe-runtime` |
| `multica` | attach_client | `controlkeel attach multica` | `local_mcp` | `none` | `inbound_only` | `agent_runtime` / `native` | `multica-native` |
| `multica-cloud` | headless_runtime | `controlkeel runtime export multica-cloud` | `hosted_mcp` | `runtime` | `runtime` | `oauth_runtime` / `instructions_only` | `multica-cloud-runtime` |
| `executor` | headless_runtime | `controlkeel runtime export executor` | `hosted_mcp` | `runtime` | `runtime` | `oauth_runtime` / `instructions_only` | `executor-runtime` |
| `virtual-bash` | headless_runtime | `controlkeel runtime export virtual-bash` | `hosted_mcp` | `runtime` | `runtime` | `ck_owned` / `instructions_only` | `virtual-bash-runtime` |
| `conductor` | framework_adapter | adapter only | `local_mcp`, `native_skills`, `commands` | `none` | `inbound_only` | `heuristic` / `native` | `claude-standalone` |
| `claude-dispatch` | alias | use `claude-code` | same as `claude-code` | same as `claude-code` | same as `claude-code` | `env_bridge` / `native` | `claude-standalone` |
| `cursor-agent` | alias | use `cursor` | same as `cursor` | same as `cursor` | same as `cursor` | `ck_owned` / `native` | `cursor-native` |
| `codex` | alias | use `codex-cli` | same as `codex-cli` | same as `codex-cli` | same as `codex-cli` | `agent_runtime` / `native` | `codex` |
| `codex-app-server` | attach_client | `controlkeel attach codex-cli` | `local_mcp`, `plugin`, `native_skills` | `embedded` | `direct` | `agent_runtime` / `native` | `codex` |
| `copilot-cli` | alias | use `copilot` | same as `copilot` | same as `copilot` | same as `copilot` | `ck_owned` / `native` | `github-repo` |
| `conductor-web` | alias | use `conductor` | same as `conductor` | same as `conductor` | same as `conductor` | `heuristic` / `native` | `claude-standalone` |
| `gemini` | alias | use `gemini-cli` | same as `gemini-cli` | same as `gemini-cli` | same as `gemini-cli` | `ck_owned` / `native` | `gemini-cli-native` |
| `kiro-cli` | alias | use `kiro` | same as `kiro` | same as `kiro` | same as `kiro` | `ck_owned` / `native` | `kiro-native` |
| `roo` | alias | use `roo-code` | same as `roo-code` | same as `roo-code` | same as `roo-code` | `ck_owned` / `native` | `roo-native` |
| `t3code` | attach_client | `controlkeel attach codex-cli` | `local_mcp`, `plugin`, `native_skills` | `embedded` | `direct` | `agent_runtime` / `native` | `codex` |
| `jcode` | unverified | research only | `local_mcp` | `none` | `inbound_only` | `none` / `instructions_only` | `instructions-only` |
| `antigravity-cli` | attach_client | `controlkeel attach antigravity-cli` | `local_mcp` | `none` | `inbound_only` | `agent_runtime` / `native` | `antigravity-cli-native` |
| `antigravity-ide` | attach_client | `controlkeel attach antigravity-ide` | `local_mcp` | `none` | `inbound_only` | `agent_runtime` / `native` | `antigravity-cli-native` |
| `clawdbot` | unverified | research only | `native_skills` | `none` | `inbound_only` | `none` / `native` | `open-standard` |
| `nous-research` | unverified | research only | `native_skills` | `none` | `inbound_only` | `none` / `native` | `open-standard` |
| `trae` | unverified | research only | `native_skills` | `none` | `inbound_only` | `none` / `native` | `open-standard` |
| `z-ai-cli` | unverified | research only | none | `none` | `inbound_only` | `none` / `none` | n/a |
| `open-agents` | framework_adapter | adapter only | `native_skills`, `cli_bash` | `none` | `inbound_only` | `heuristic` / `native` | `open-standard` |
| `cloudflare-workers` | headless_runtime | `controlkeel runtime export cloudflare-workers` | `hosted_mcp` | `runtime` | `runtime` | `ck_owned` / `instructions_only` | `cloudflare-workers-runtime` |

The shipped `copilot` attach target is the repo-native path for GitHub Copilot, and the exported `copilot-plugin` bundle is the same companion path used for GitHub Copilot CLI and VS Code agent mode.

All shipped attach/runtime rows currently use `policy_gated` autonomy. `/skills` and `GET /api/v1/skills/targets` expose the exact code-backed values as `agent_uses_ck_via`, `ck_runs_agent_via`, `execution_support`, and `autonomy_mode`.

Provider backends now flow through provider configuration (`base_url`, `model`, and credentials) instead of separate integration rows. Add a catalog row only when CK ships an attach/export/runtime surface for that backend.

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

## Cloud-capable runtime surfaces

Runtime surfaces that already support hosted MCP, A2A, or service-account-driven remote access are marked cloud-capable. These surfaces can run against a shared CK instance when the matching hosted runtime loop is configured.

| Runtime | Export command | Cloud protocol support | Status |
| --- | --- | --- | --- |
| `devin` | `controlkeel runtime export devin` | Hosted MCP, A2A | Shipped (headless runtime) |
| `open-swe` | `controlkeel runtime export open-swe` | Hosted MCP, A2A | Shipped (headless runtime) |
| `warp-oz` | `controlkeel runtime export warp-oz` | Hosted MCP, native skills, rules | Shipped (headless runtime) |
| `executor` | `controlkeel runtime export executor` | Hosted MCP, A2A | Shipped (headless runtime) |
| `virtual-bash` | `controlkeel runtime export virtual-bash` | Hosted MCP, commands | Shipped (headless runtime) |
| `cloudflare-workers` | `controlkeel runtime export cloudflare-workers` | Hosted MCP | Shipped (headless runtime) |
| `forge` | `controlkeel attach forge` | Hosted MCP, A2A | Shipped (attach client) |

Attach clients that use only local stdio MCP (`local_mcp` only) are local-first and do not require cloud connectivity. They can participate in cloud governance through hybrid local-agent plus hosted-governance sync when configured.

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
| `ck_execute_code` | local/stdio MCP only; not exposed through hosted MCP or A2A until remote sandbox enforcement is available |
| `ck_finding` | `mcp:access`, `finding:write` |
| `ck_review_submit` | `mcp:access`, `review:write` |
| `ck_review_status` | `mcp:access`, `review:read` |
| `ck_review_feedback` | `mcp:access`, `review:respond` |
| `ck_experience_index`, `ck_experience_read`, `ck_trace_packet`, `ck_failure_clusters`, `ck_tool_health`, `ck_skill_evolution`, `ck_fs_ls`, `ck_fs_read`, `ck_fs_find`, `ck_fs_grep` | `mcp:access`, `context:read` |
| `ck_regression_result` | `mcp:access`, `regression:write` |
| `ck_memory_search` | `mcp:access`, `memory:read` |
| `ck_memory_record`, `ck_memory_archive` | `mcp:access`, `memory:write` |
| `ck_budget` | `mcp:access`, `budget:write` |
| `ck_route` | `mcp:access`, `route:read` |
| `ck_delegate` | `mcp:access`, `delegate:run` |
| `ck_cost_optimizer` | `mcp:access`, `cost:read` |
| `ck_outcome_tracker` | `mcp:access`, `outcome:read`, `outcome:write` |
| `ck_skill_list`, `ck_skill_load` | `mcp:access`, `skills:read` |

`ck_execute_code` and `ck_deployment_advisor` are intentionally not exposed through hosted MCP yet. `ck_execute_code` requires a local Docker sandbox boundary, and `ck_deployment_advisor` currently operates on an arbitrary `project_root` path rather than a session-bound workspace root.

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
- capability egress posture is default-deny; network/high-impact grants are expected to be explicit, task-scoped, and review-traceable

Hosts may still expose their own file-backed memory surfaces, such as repo memory files or mounted working directories. CK treats those as companion execution surfaces, not as the governed system of record. Durable reviewable continuity still lives under `typed_storage`.

## MCP runtime tools

Implemented under [`lib/controlkeel/mcp/tools/`](../lib/controlkeel/mcp/tools/). The MCP server advertises the core and extended governance tools, and adds `ck_skill_list` and `ck_skill_load` when the runtime has a non-empty skill catalog (see `protocol.ex` `tool_schemas/0`).

| Tool | Purpose |
| ------ | --------- |
| `ck_attach` | Wire ControlKeel into the current agent host (Claude Code, Cursor, Codex, OpenCode, etc.). Closes the gap for users who installed ControlKeel via a one-line MCP-add command but skipped `controlkeel attach <host>`. Installs the host-specific hooks (SessionStart, PreToolUse, PostToolUse, UserPromptSubmit), skills directory, slash commands, AGENTS.md/CLAUDE.md preamble, and subagent profiles for the requested host. Idempotent — re-running refreshes artifacts to the current version. Writes only inside `project_root`; no network egress. Call this once after a one-line MCP install when the host lacks ControlKeel hooks/skills. Use `ck_mcp_discover` first if unsure which host ID to pass. |
| `ck_budget` | Estimate, record, or check the cost of an agent operation against session and daily spend budgets. Three modes: estimate (read-only, returns headroom and projected cost); commit (write — deducts estimated_cost_cents from the session budget); status (read-only, returns remaining budget). For commit mode: pass session_id, estimated_cost_cents, provider, model, input_tokens, and output_tokens. Pass include_token_overhead: true with project_root to attach a token overhead audit (rule files, skill duplicates, tool schemas) to the response. Check ck_budget before expensive multi-agent work or large model calls. Use ck_cost_optimizer for model price comparisons without recording spend. |
| `ck_checkpoint_create` | Create a workspace checkpoint capturing git state, workspace context, and metadata for migration or rollback. |
| `ck_checkpoint_list` | List all checkpoints for a session, optionally filtered by type. |
| `ck_checkpoint_restore` | Restore session state from a previous checkpoint, updating session metadata with checkpoint information. |
| `ck_context` | Fetch the full governed session state: mission, budget, active findings, proof summary, planning context, workspace snapshot, drift signals, recent transcript events, resume packet, and ControlKeel instruction hierarchy. Read-only. detail_level compact (default) returns a token-efficient summary; use full only when raw workspace, resume, or transcript payloads are required. session_id defaults to the active bound session; pass project_root to resolve it automatically. Call ck_context at the start of every task to reacquire state. Prefer ck_context_pack when you need a focused, citation-enriched bundle for a specific retrieval query rather than the full session snapshot. |
| `ck_context_pack` | Build a compact, citation-enriched context bundle for the current session and task by combining task facts, proof state, resume highlights, and ranked memory excerpts. Read-only. query is an optional retrieval query; when omitted, ControlKeel synthesizes one from the current task title and session context. top_k controls how many memory hits to include (default 5). detail_level compact (default) keeps the bundle token-efficient. Prefer ck_context_pack over ck_context when you need a focused, query-driven bundle for a specific sub-task rather than the full session snapshot. Use ck_context at the start of a session for full mission state; use ck_context_pack mid-task to fetch targeted prior knowledge. |
| `ck_copilot` | Real-time collaborative channel where human actions stream to the agent. Build software for humans and agents to use together — agents can see when a human is viewing, editing, or approving. Modes: subscribe (receive events), publish (emit an event), presence (who is active), history (recent events). |
| `ck_cost_optimizer` | Get cost optimization suggestions or compare AI provider/model prices for a task. Read-only — no budget records are written (use ck_budget to record actual spend). Two modes: suggest returns optimization tips based on recent session spending patterns; compare returns a side-by-side price breakdown for the given task. For suggest mode, pass session_id. For compare mode, pass task_description and estimated_tokens along with top_provider and top_model as the baseline. Use ck_cost_optimizer before choosing a model for expensive multi-agent work; use ck_budget to record and enforce spend limits. |
| `ck_delegate` | Hand off a governed task or session to another AI agent, transferring governance context (findings, budget, proofs) to the target. Mutates session state to reflect the delegation. Four modes: auto (ControlKeel picks the best agent), embedded (inline sub-agent), handoff (transfer session ownership), runtime (delegate to a pre-configured runtime agent). agent is the target agent ID (e.g., claude, opencode, cursor). Call ck_route first to identify the best agent, then ck_delegate to transfer. Prefer ck_route when you only need a recommendation without transferring; prefer ck_delegate when you are ready to hand off execution. |
| `ck_deployment_advisor` | Analyze the project stack and suggest deployment platforms, or generate CI/CD and Docker configuration files. Three modes: analyze (read-only, returns platform recommendations based on detected stack); generate_files (write operation, creates Dockerfile and CI/CD configs in the project); dns_guide (read-only, returns DNS setup instructions for the recommended platform). project_root is required. Set dry_run: true with generate_files to preview what would be created without writing files. Use ck_deployment_advisor before deploying a new project or when setting up CI/CD for the first time. For budget and cost checks before deployment, use ck_budget. |
| `ck_execute_code` | Execute generated code only inside a configured non-local sandbox. Defaults to Docker, denies network/filesystem/secrets/shell/deploy, validates source first, and supports dry_run for planning. |
| `ck_experience_index` | List recent prior sessions in the same workspace and the read-only experience artifacts available for each run. Pass `query` for freeform keyword search across session titles, task titles, and finding descriptions — useful for questions like 'has this deployment pattern caused a blocked finding before?' |
| `ck_experience_read` | Read one prior-run artifact such as a session summary, audit log, trace packet, or proof summary from the workspace experience archive. |
| `ck_experience_search` | Freeform full-text search across findings and tasks within the current workspace. Returns ranked results with citations. Useful for questions like 'has this deployment pattern caused a blocked finding before?' or 'what did we do about the SQL performance issue?' |
| `ck_external_service` | Track and govern agent interactions with external SaaS APIs. Rate limits per service, cost attribution, and PII redaction. Modes: record (log an interaction with auto-redaction), summary (aggregated view per service), rate_limit_status (current rates against limits), top_services (ranked by volume and cost). |
| `ck_failure_clusters` | Cluster recurring failure modes across recent session traces in the same workspace and return reusable eval candidates. |
| `ck_finding` | Persist a governed finding with a ruling decision (allow, warn, block, escalate_to_human). Findings are the durable audit trail in ControlKeel: every policy check, validation failure, or human review should produce a finding. Write operation — creates or updates a DB record. Idempotent for the same rule_id within a session. Returns the finding ID, status, and ruling state. Required fields: session_id, category (e.g., security/compliance/performance), severity (critical/high/medium/low), rule_id (dotted policy identifier such as CK-SEC-001), and plain_message. decision defaults to block; use allow for approved exceptions. Use ck_finding to record issues discovered during agent work; use ck_memory_record for general knowledge or decisions not tied to a policy rule. |
| `ck_fs_find` | Find files or directories whose path contains a given fragment, searching within the bound project root. Read-only — no files are modified. query is the path fragment or glob pattern to match against file and directory names. path scopes the search to a subdirectory (relative to project root); omit to search the entire project. limit caps the number of results (default 50). Use ck_fs_find to locate files by name or path. Use ck_fs_grep to search by file content. Use ck_fs_read to read a file at a known path. |
| `ck_fs_grep` | Search file contents inside the bound project root using grep-style pattern matching. Read-only — no files are modified. query is a regex pattern by default; set fixed_strings: true to match literal text without regex. Scope the search with path (a relative directory or glob); omit to search the entire project. Returns matching lines with file path and line numbers. limit caps results (default 50). Use ck_fs_grep to find code patterns or strings inside files. Use ck_fs_find to locate files by name fragment. Use ck_fs_read to read a specific file by path. |
| `ck_fs_ls` | List files and directories inside the bound project root. Read-only — no files are modified. path is a relative directory path to list; omit to list the project root. Use ck_fs_ls to browse directory structure. Use ck_fs_find to locate files by name fragment. Use ck_fs_read to read a specific file. Use ck_fs_grep to search file contents. |
| `ck_fs_read` | Read a file from the bound project root. Read-only — no files are modified or created. path is required and must be relative to the project root (e.g., lib/my_module.ex). start_line (1-indexed) and max_lines enable windowed reads for large files. Omit both to read the entire file. Use ck_fs_read to inspect a file at a known path. Use ck_fs_find to locate a file by name fragment. Use ck_fs_grep to search inside files by content pattern. Use ck_fs_ls to list directory contents. |
| `ck_git_commit` | Validate a commit message against CK governance policy and execute git commit if validation passes and no findings are blocked. Write operation — creates a git commit in the repository when validation succeeds. Returns validation result, any blocked findings, and the commit SHA on success. If blocked findings exist, the commit is not created and the findings are returned for remediation. Use ck_git_status first to confirm governance state, then ck_git_commit to create the commit. Does not push to remote — use git push separately after commit. |
| `ck_git_diff` | Generate a git diff and run CK validation on the resulting diff. Read-only — no commits are created. base_ref and head_ref are git refs (branch names, commit SHAs, or tags); omit both or pass empty strings to diff the working tree against HEAD. Returns the diff text and any CK validation findings raised against it. Use ck_git_diff to review changes before committing or submitting a review. Use ck_git_status for a summary without the full diff. Use ck_git_commit to create the commit after reviewing. |
| `ck_git_status` | Get git working tree status correlated with CK governance findings for the current session. Returns staged, unstaged, and untracked files alongside any blocked or open findings from ck_validate or ck_review_submit. Read-only and side-effect free — no findings are created or modified. Use before ck_git_commit to verify governance state. Prefer ck_git_diff when you need the actual diff content; prefer ck_git_commit when ready to commit. |
| `ck_goal` | Record, list, or update durable governed goals so long-running intent stays explicit, citable, and reviewable across sessions. Three modes: record (write — creates a new goal); list (read-only — returns goals filtered by status and horizon); update_status (write — updates an existing goal's status or progress). Required: session_id and mode. For record: provide goal (the statement text) and optionally title, horizon (task/session/workspace), and tags. For update_status: provide goal_id and the new status. horizon controls scope: task for short-lived intent, session for the current session, workspace for persistent cross-session goals. Use ck_goal for structured multi-session intent that should be explicitly tracked and reviewed. Use ck_memory_record for general decisions or notes not requiring status tracking. |
| `ck_load_resources` | Fallback for clients that do not support MCP resources. Load one or more CK resource URIs such as skills://<name>. |
| `ck_mcp_discover` | Auto-discover tools from an external MCP server by querying its tools/list endpoint. This enables progressive discovery of MCP capabilities without manual configuration. |
| `ck_memory_archive` | Archive a memory record so it is excluded from future ck_memory_search results. Write operation — marks the record as archived in the database; it is not deleted. memory_id is the integer ID returned by ck_memory_record or ck_memory_search. Use when a record is stale, superseded by a newer decision, or contains information that should no longer guide future agents. To update a record's content instead of archiving it, call ck_memory_record again with the same source_id. |
| `ck_memory_record` | Write a governed memory record so future agents can explicitly retrieve it via ck_memory_search. Write operation — persists to the database. Idempotent: re-submitting the same source_id updates the existing record rather than duplicating it. Pass memory as a plain string for quick notes, or as an object with body, title, summary, record_type, and tags for structured records. record_type controls retrieval filtering: use decision for architectural choices, finding for issues, proof for evidence, goal for intent, brief for task context. tags is a string or array of strings for categorization. source_id links the record to an external artifact (e.g., a review ID or commit SHA). Use ck_memory_record to persist knowledge that should survive session boundaries. Use ck_finding for policy violations with a ruling decision. Use ck_goal for durable multi-session intent. |
| `ck_memory_search` | Search governed typed memory for the current session to recover prior decisions, findings, proofs, and domain knowledge. Read-only. query is a freeform text search applied across record titles, bodies, and tags. record_type filters by type (decision, finding, proof, goal, brief, checkpoint); omit to search all types. top_k limits the number of ranked results (default 10). source_type and source_id filter by origin. Returns ranked records with citations and scores. Use ck_memory_search to retrieve what was recorded in prior steps or sessions. Use ck_memory_record to write new records. Use ck_experience_search for full-text search across findings and tasks workspace-wide. |
| `ck_observability` | Read local observability reports for sessions, loop status, problems, memory, costs, trends, evals, generated benchmarks, history, and advisory promotion candidates. Read-only: no benchmark execution, draft approval, materialization, or promotion mutation. |
| `ck_outcome_tracker` | Record session outcomes or retrieve agent performance leaderboards to close the reinforcement-learning feedback loop. Three modes: record persists a session outcome (write operation); get_session reads a specific outcome by session_id (read-only); get_leaderboard returns ranked agent performance (read-only). For record mode: pass session_id, outcome (success/partial/failure), agent_id, and task_type. For get_leaderboard: pass workspace_id and optional window (days) and limit. Call after task completion before ending the session so ck_route and ck_cost_optimizer have fresh performance data for future routing decisions. |
| `ck_regression_result` | Record external regression-test evidence from CI/CD systems (Bug0, Passmark, custom runners) so proof bundles and release-readiness checks account for external validation. Write operation — creates a DB record. Returns the recorded result ID. Required: session_id, engine (name of the test system), flow_name (test suite or flow identifier), outcome (passed/failed/flaky/skipped). Optional: commit_sha to link results to a specific revision, environment (ci/staging/production), external_run_id for cross-referencing the originating system, evidence for a structured payload. Use after an external test run to close the proof loop before calling ck_review_submit for a completion review. Retrieve past results with ck_memory_search using record_type: regression. |
| `ck_result_peek` | Peek at the full stdout of a previously completed ck_delegate embedded run without loading it all into context. Use result_ref and package_root returned by ck_delegate to locate the stored output. Supports byte-range reads: pass peek_bytes to limit how much to load, and offset to skip ahead. Use result_length (returned by ck_delegate) to decide whether to peek, pass the ref downstream, or skip loading entirely. This is the RLM variable-encapsulation pattern: treat large sub-agent outputs as named references, not inline blobs. |
| `ck_review_feedback` | Approve or deny a submitted review and attach feedback notes or structured annotations. Write operation — updates the review record and unblocks or halts the execution gate. review_id (required) is the ID returned by ck_review_submit. decision must be approved or denied. feedback_notes is freeform text for the reviewer's rationale. annotations is a key-value object for machine-readable metadata. This tool is human-facing: agents call ck_review_submit to create a review, then a human (or authorized agent) calls ck_review_feedback to record the decision. After approval, the submitting agent can proceed with execution; after denial, the plan should be revised and resubmitted. |
| `ck_review_status` | Fetch the latest decision status (pending/approved/denied), reviewer notes, and browser review URL for a previously submitted review. Read-only. Provide review_id (returned by ck_review_submit) for a specific review, or task_id to get the latest review for that task. review_type (plan/diff/completion) filters when task_id is used without review_id. Poll this after ck_review_submit to check whether a human has approved or denied the submission before proceeding with execution. |
| `ck_review_submit` | Submit a governed plan, diff, or completion packet for human review and execution gating. Write operation — creates a review record and returns a review_id and browser URL. review_type controls what is being submitted: plan (before implementation), diff (before merging), or completion (task done). submission_body is the full content: plan text, diff, or completion description. For iterative plan refinement, pass previous_review_id and plan_phase (ticket → research_packet → design_options → narrowed_decision → implementation_plan → code_backed_plan). The plan-quality scorer evaluates structured fields, not just submission_body — populate research_summary, options_considered, selected_option, rejected_options, implementation_steps, validation_plan, code_snippets, alignment_context, consulted_roles, codebase_findings, prior_art_summary, and scope_estimate for a strong score. Returns review_id, status (pending), and a URL where the human reviewer can approve or deny. After submission, poll ck_review_status until the decision is approved or denied before proceeding. Use ck_review_feedback (human-facing) to record a decision on an existing review. |
| `ck_rollback` | Execute a governed rollback of an agent's work. Records a git checkpoint before each task and provides a single action to revert. Safety-checked: refuses if downstream tasks depend on the changes. Creates an audit finding on every rollback. Modes: checkpoint (capture git HEAD before task), execute (revert agent's changes), status (check snapshot state), list (all snapshots for session). |
| `ck_loop` | Govern an objective bounded loop with immutable verifier hashes, fresh sandbox evidence, hard limits, and independent promotion review; worker execution remains separate. |
| `ck_route` | Recommend the best available AI agent for a given task based on security tier, remaining budget, task type, and past performance data. Read-only — no session state is changed. task is a plain-language description of what needs to be done. risk_tier (low/medium/high/critical) filters out agents that are not cleared for the security level; defaults to medium. allowed_agents restricts routing to a specific subset of agent IDs; omit to allow all. Returns a ranked list of agent recommendations with rationale. Use ck_route to pick an agent, then ck_delegate to transfer the task. Use ck_cost_optimizer for a price-focused comparison without routing. |
| `ck_session_digest` | Generate a condensed, human-scannable digest of what happened in a session — tasks completed, findings raised, budget spent, reviews pending, and notable highlights. Three modes: generate (create a new digest), latest (return the most recent), list (paginated history). Designed for the forward-deployed engineer who needs an 'inbox that summarizes what happened' without reading raw event streams. |
| `ck_skill_evolution` | Synthesize a deduplicated skill-evolution packet from recent traces and recurring failure clusters, including anti-patterns, reinforced practices, and a ready-to-merge skill draft. |
| `ck_skill_list` | List all available AgentSkills for this project. Returns names, descriptions, and scopes. Call this to discover capabilities you can activate, then use ck_skill_load to load a skill's full instructions. |
| `ck_skill_load` | Load the full instructions for a named AgentSkill. Returns the SKILL.md body wrapped in <skill_content> tags plus a list of bundled resource files. Call after ck_skill_list to activate a specific skill. |
| `ck_skill_validate` | Validate skill output against a JSON Schema defined in the skill's result-schema frontmatter field. Skills can define a result_schema in their frontmatter; agents call this tool after running a skill to enforce typed, structured output. Accepts output + schema directly, or output + skill_name to validate against the skill's built-in schema. |
| `ck_token_audit` | Audit project rule files (AGENTS.md, CLAUDE.md, etc.) and skills for token overhead. Returns word counts, token estimates, duplicate detection, and optimization recommendations. |
| `ck_tool_health` | Analyze governance coverage across recent sessions in the workspace — which CK governance tools (ck_validate, ck_review_submit, ck_budget, ck_memory_record, ck_goal) are load-bearing, active, low-usage, or unused — and return actionable recommendations for gaps. |
| `ck_trace_packet` | Export a structured session or task trace packet with failure patterns and eval candidates for trace-centered improvement loops. |
| `ck_validate` | Validate proposed code, config, shell commands, or text against CK policy before execution. Read-only — no changes are applied to the project. Returns a validation result with any policy violations as findings. content is required. kind classifies the artifact (code/config/shell/text) for policy routing. source_type identifies the content's origin (developer, tool_output, human_review, issue, pull_request, web) for trust-boundary checks; untrusted sources receive stricter scrutiny. domain_pack applies a domain-specific policy pack (e.g., hipaa, owasp). requested_capabilities declares what the content needs (network, filesystem, shell, deploy) so the trust boundary can evaluate the request. Call ck_validate before writing files, running shell commands, or executing generated code. If validation returns blocked findings, do not proceed — use ck_finding to record them. |
| `ck_workspace_agent` | Manage workspace agent roles: one primary 'super-agent' per workspace maintained by a forward-deployed engineer, specialized agents for specific domains, and ephemeral agents for short-lived tasks. Modes: register (create agent, only one primary per workspace), update (change scope/budget/status), list (all agents for workspace), health (aggregated health indicator), retire (deactivate agent). |
| `ck_worktree_list` | List all git worktrees in the current repository with their branch, HEAD, and status information. |
| `ck_worktree_switch` | Switch the current session to a different git worktree and update session metadata accordingly. |

Authoritative tool names in code are split between `ControlKeel.Distribution.required_mcp_tools/0` (core required set) and `ControlKeel.Mcp.Protocol.tool_schemas/0` (advertised runtime surface, including extended governance tools).

## Bundled skills (`priv/skills/`)

These directories ship with the repo and are discovered by [`ControlKeel.Skills.Registry`](../lib/controlkeel/skills/registry.ex):

| Skill directory | Role |
| ----------------- | ------ |
| `agent-integration` | Agent integration workflows and references (e.g. target matrix). |
| `agent-pattern-verification` | AI agent code pattern verification. |
| `align` | Pre-work alignment interview. |
| `architect-first` | Architect-first module design. |
| `benchmark-operator` | Benchmark operator playbooks. |
| `bounded-loop` | Verifier-isolated, budgeted iterative improvement workflow. |
| `challenge` | Adversarial plan challenge. |
| `cli-for-agents` | CLI design for agent-friendliness. |
| `cloudflare-agent` | Cloudflare agent governance. |
| `communication-style` | Concise, evidence-preserving technical communication. |
| `compliance-audit` | Compliance / control matrix audits. |
| `continual-learning` | Session learning and memory. |
| `continuity` | Codebase pattern continuity. |
| `controlkeel-governance` | Governance workflow references. |
| `cost-optimization` | Budget and cost playbooks. |
| `deep-code-quality-review` | Deep maintainability review. |
| `deslop` | AI slop cleanup. |
| `domain-audit` | Domain-specific review matrices. |
| `end-of-shift` | Governed validation, proof, digest, and handoff closure. |
| `false-confidence-test-audit` | Evidence-based audit of tests that may pass without proving behavior. |
| `handoff` | Session state handoff. |
| `investigate` | Read-only codebase Q&A. |
| `orchestrate-tasks` | Parallel task orchestration. |
| `parallel-review` | Concurrent security + quality review. |
| `plan-slice` | Vertical slice decomposition. |
| `proof-memory` | Proof bundles and typed memory workflow. |
| `reviewable-pr` | PR preparation for review. |
| `security-review` | Security review checklist. |
| `ship-readiness` | Release / ship checklist. |
| `standup-summary` | Work summary and standup. |
| `tdd-bugfix` | TDD bugfix workflow. |

Export targets on each integration (e.g. `claude-plugin`, `codex`) refer to **CLI** `controlkeel skills export --target …` bundles, not separate MCP tools.

## Adding a new attach target (maintainers)

1. Confirm a **documented** MCP or config file location for that client.
2. Add a new `integration(...)` entry to `Agent.Integration.catalog/0` with accurate `provider_bridge`, `supported_scopes`, and `export_targets`.
3. Wire CLI `attach` for that id if not already present in [`lib/controlkeel/cli.ex`](../lib/controlkeel/cli.ex) (or runtime attach module).
4. Update this matrix and [agent-integrations.md](agent-integrations.md).
5. Add or extend tests for attach behavior where feasible.

Historical research names do **not** automatically get catalog entries. A target becomes shipped support only after it has a documented config surface, a truthful `Agent.Integration` row, CLI/export coverage, docs, and tests.
