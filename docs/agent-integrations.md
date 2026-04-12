# ControlKeel Agent Integrations

This document explains how ControlKeel models integrations without repeating the full inventory in multiple places.

Use the more specific docs for the concrete question you have:

- [getting-started.md](getting-started.md): install ControlKeel and attach your first host
- [direct-host-installs.md](direct-host-installs.md): package, plugin, VSIX, and extension-link install paths
- [support-matrix.md](support-matrix.md): canonical code-aligned host and protocol inventory
- [host-surface-parity.md](host-surface-parity.md): why the current host surfaces were chosen

## Support by mechanism

ControlKeel supports agent ecosystems through a few distinct mechanisms:

- **Native attach**: `controlkeel attach <host>` installs MCP config plus the strongest repo-native companion CK can truthfully ship.
- **Direct host install**: some hosts also expose a package, plugin, VSIX, or extension-link path.
- **Hosted protocol access**: remote clients can use hosted MCP and minimal A2A instead of repo-local stdio MCP.
- **Runtime export**: headless runtimes and governed outer-loop recipes such as Devin, Open SWE, Executor, and `virtual-bash` get runtime bundles rather than fake attach commands.
- **Provider-only and fallback governance**: unsupported tools can still be governed through bootstrap, findings, proofs, provider profiles, and validation APIs.

That mechanism split is intentionally simpler than the full catalog, but it should always match the canonical [support-matrix.md](support-matrix.md).

## Bidirectional execution model

Each integration is modeled in both directions:

- **How the agent uses CK**: `local_mcp`, `hosted_mcp`, `a2a`, `plugin`, `native_skills`, `rules`, `workflows`, `hooks`, or `proxy`
- **How CK runs the agent**: `embedded`, `handoff`, `runtime`, or `none`
- **What autonomy is truthful**: `direct`, `handoff`, `runtime`, or `inbound_only`

The practical meaning is:

- **direct**: CK can launch a locally verifiable command surface and keep the run policy-gated.
- **handoff**: CK prepares the governed bundle, credentials, and task package, then waits for the external host to continue.
- **runtime**: CK talks to a remote or headless runtime and tracks the run through the same governed task primitives.
- **inbound_only**: the agent can use CK, but CK does not currently drive that agent.

Blocked findings and explicit approval constraints still stop all modes.

## First-class host adapters

These are the current higher-confidence host adapters where the docs, release assets, and review path are intentionally aligned:

| Host | Attach command | Review path | Strongest shipped surface |
| --- | --- | --- | --- |
| Claude Code | `controlkeel attach claude-code` | native hook review | plugin bundle plus `.claude/skills` and `.claude/agents` |
| GitHub Copilot | `controlkeel attach copilot` | native hook and repo review | repo-native `.github/*` plus Copilot plugin bundle |
| OpenCode | `controlkeel attach opencode` | plugin tool review | repo-native `.opencode/*` and published npm companion |
| Augment / Auggie CLI | `controlkeel attach augment` | plugin and hook review | repo-native `.augment/*` plus local plugin bundle |
| Pi | `controlkeel attach pi` | browser review with persisted plan state | file-plan bundle and published npm extension |
| VS Code | `controlkeel attach vscode` | browser review through companion webview | companion `.vsix` plus repo-local MCP wiring |
| Codex CLI | `controlkeel attach codex-cli` | browser review through native commands | `.codex/config.toml`, `.codex/agents`, `.codex/commands`, plus optional local plugin bundle via `controlkeel plugin install codex` |

For Codex there are two supported CK delivery modes:

- `controlkeel attach codex-cli`
  Uses Codex-native MCP, skills, commands, and agent files inside `.codex/`.
- `controlkeel plugin install codex`
  Installs a local plugin bundle plus a local marketplace manifest. This is a repo-local or home-local marketplace entry, not the same thing as appearing in Codex's curated remote plugin catalog.

When a user says "I don't see CK in the Codex plugins page," the most likely explanation is that they are looking at the curated catalog or a workspace-managed app surface, while CK was installed as a local bundle. In that case the truthful next checks are:

1. Verify the local plugin exists under `plugins/controlkeel` or `~/plugins/controlkeel`
2. Verify the matching marketplace manifest exists at `.agents/plugins/marketplace.json` or `~/.agents/plugins/marketplace.json`
3. If the goal is dependable local Codex behavior rather than plugin-catalog discovery, prefer `controlkeel attach codex-cli`

For the exhaustive fields behind those rows, including phase model, runtime transport, package outputs, and execution support, use [support-matrix.md](support-matrix.md).

## Broader native host coverage

ControlKeel also ships stronger repo-native surfaces for hosts whose official UX is based on rules, commands, hooks, workflows, or extension manifests rather than a package marketplace.

Current examples:

- Windsurf: hooks, workflows, commands, and MCP config
- Continue: prompts, command prompts, headless guidance, and MCP server config
- Letta Code: project skills, checked-in hook settings, `/mcp add` helper script, and remote/headless guidance
- Cline: hooks, commands, rules, and workflow guidance
- Goose: hints, workflow recipes, commands, and extension YAML
- Kiro: hooks, steering, tool policy settings, and commands
- Kilo Code: Agent Skills, slash-command workflows, MCP config, and `AGENTS.md`
- Amp: TypeScript plugin scaffold, native skill bundle, commands, and MCP wiring
- Gemini CLI: extension manifest, commands, skills, and `GEMINI.md`
- Cursor: rules, commands, background-agent guidance, and MCP config
- Roo Code: rules, commands, governed modes, and cloud-agent guidance
- Aider: command-driven review snippets and `.aider.conf.yml`

These are real shipped surfaces, but they are not all published marketplaces or npm packages. That distinction is why [direct-host-installs.md](direct-host-installs.md) exists separately.

The same distinction applies to the broader `skills.sh` ecosystem. Some names there map directly to shipped CK targets such as `codex` -> `codex-cli`, `gemini` -> `gemini-cli`, `kiro-cli` -> `kiro`, `kilo` -> `kilo`, and `roo` -> `roo-code`. Other names such as `antigravity`, `clawdbot`, `nous-research`, and `trae` are currently skills-compatible only through open-standard AgentSkills installs, not through a native CK attach/runtime contract.

Conductor sits between those buckets. Its official docs say it runs bundled Claude Code and Codex, uses Claude Code MCP config, maps project instructions to `CLAUDE.md`, and reads Claude slash commands from `.claude/commands`. In practice that means CK support inside Conductor is real, but it is inherited from the Claude Code repo-local surfaces rather than from a dedicated `controlkeel attach conductor` command.

Paperclip is one layer higher again: an orchestration plane that schedules and supervises external agents through documented adapters such as Claude Local, Codex Local, Gemini Local, OpenClaw Gateway, Hermes Local, Pi Local, and Cursor Local, with instance config under `~/.paperclip/instances/default/config.json`. CK therefore models Paperclip as an orchestration adapter, not as a native attach target. The practical integration path is to attach CK to the underlying runtime each Paperclip agent uses.

## Protocol interop

ControlKeel exposes three protocol surfaces around the integration catalog:

- **Local stdio MCP** for repo-local trust and native attach flows
- **Hosted MCP** for service-account-driven remote clients
- **Minimal A2A** for agent-card discovery and narrow JSON-RPC message dispatch

Hosted MCP uses:

- `POST /mcp`
- `GET /.well-known/oauth-protected-resource/mcp`
- `GET /.well-known/oauth-protected-resource`
- `GET /.well-known/oauth-authorization-server`
- `POST /oauth/token`

Minimal A2A uses:

- `GET /.well-known/agent-card.json`
- `GET /.well-known/agent.json`
- `POST /a2a`

It advertises the current governed capabilities only:

- `ck_context`
- `ck_validate`
- `ck_finding`
- `ck_review_submit`
- `ck_review_status`
- `ck_review_feedback`
- `ck_budget`
- `ck_route`
- `ck_delegate`

For skills, CK now supports both discovery patterns:

- MCP `resources/list` and `resources/read` expose skills as `skills://<name>` resources for clients that support MCP resources
- `ck_load_resources` is the tool fallback for clients that only support tool calls
- `ck_skill_list` and `ck_skill_load` remain the explicit skill-catalog surfaces and are still useful when the client wants typed compatibility metadata before loading content

In practice, `ck_context` is the main continuity surface across those transports. It returns current mission state plus a bounded workspace snapshot, a deterministic workspace cache key, recent CK-visible transcript events, transcript summaries, and resumable task context for the active session.

ACP registry support is supplemental only:

- `controlkeel registry sync acp`
- `controlkeel registry status acp`

Registry data enriches existing targets with freshness and metadata. It does not invent new attach flows or override the built-in catalog.

## Governed execution surfaces

ControlKeel can also drive agents where the execution path is truthful:

- `controlkeel agents doctor`
- `controlkeel run task <id> [--agent auto|<id>] [--mode auto|embedded|handoff|runtime]`
- `controlkeel run session <id> [--agent auto|<id>]`
- `GET /api/v1/agents`
- `POST /api/v1/tasks/:id/run`
- `POST /api/v1/sessions/:id/run`
- `ck_delegate` over hosted MCP or A2A when the caller has `delegate:run`

Execution remains policy-gated. CK does not bypass blocked findings or explicit approval requirements just because a runtime surface exists.

## Proxy-compatible clients

ControlKeel also exposes governed proxy endpoints for OpenAI-style and Anthropic-style traffic. This is useful for tools that can point directly at those APIs, but it is a different support tier from a native attach target or documented provider bridge.

Supported proxy shapes today:

| Upstream shape | Path on ControlKeel |
| --- | --- |
| OpenAI Responses API | `/proxy/openai/{proxy_token}/v1/responses` |
| OpenAI Chat Completions | `/proxy/openai/{proxy_token}/v1/chat/completions` |
| OpenAI Embeddings | `/proxy/openai/{proxy_token}/v1/embeddings` |
| OpenAI Models | `/proxy/openai/{proxy_token}/v1/models` |
| Anthropic Messages | `/proxy/anthropic/{proxy_token}/v1/messages` |
| OpenAI Realtime | `/proxy/openai/{proxy_token}/v1/realtime` |

Treat proxy support as API-shape compatibility, not as proof of a full native integration.

## Other supported intake surfaces

Socket.dev findings can be ingested directly into the same governed finding model:

- `controlkeel review socket --report socket-report.json`
- `cat socket-report.json | controlkeel review socket --stdin`

This keeps dependency-risk intake in the same review and proof flow as code findings.

## Non-attach surfaces

The catalog also includes rows that are intentionally not marketed as attach targets:

| Support class | What it means |
| --- | --- |
| Headless runtime | `controlkeel runtime export <target>` writes governed runtime bundles for systems such as Devin, Open SWE, Executor, and CK-owned virtual runtime recipes |
| Framework adapter | surfaced through benchmark, policy, or runtime-harness adapter exports rather than host attach; this is where orchestration layers such as Conductor and Paperclip sit |
| Provider-only | CK provider profiles and OpenAI-compatible backend guidance for systems such as Ollama, vLLM, SGLang, LM Studio, Hugging Face, and Codestral-compatible endpoints |
| Alias | maps ecosystem names back to the canonical shipped target |
| Unverified | visible for research honesty, but not marketed as shipped support |

## Fallback governance

Unsupported tools still have a truthful recovery path:

1. bootstrap a governed project
2. let the external tool make changes
3. use `controlkeel watch`, `controlkeel findings`, proofs, and `ck_validate`
4. use proxy mode when the tool can target OpenAI- or Anthropic-compatible endpoints

That keeps the support story honest: not every tool gets a first-class attach command, but unsupported tools can still participate in the governance loop.

For Conductor specifically, the practical recommendation is:

1. run `controlkeel attach claude-code` in the repository you open in Conductor
2. let Conductor consume the resulting `.mcp.json`, `CLAUDE.md`, and `.claude/commands`
3. use Conductor workspaces as isolated branches/worktrees while CK stays the governance layer
