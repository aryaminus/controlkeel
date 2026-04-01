# ControlKeel Agent Integrations

This is the current ControlKeel distribution and attachment matrix.

**Canonical inventory:** [support-matrix.md](support-matrix.md) lists every `AgentIntegration.catalog/0` row, all MCP runtime tools, and `priv/skills/` bundles in one place. Use it when aligning docs with code.

## Install ControlKeel

ControlKeel itself is distributed through GitHub Releases, with convenience install channels layered on top:

```bash
brew tap aryaminus/controlkeel && brew install controlkeel

npm i -g @aryaminus/controlkeel
pnpm add -g @aryaminus/controlkeel
yarn global add @aryaminus/controlkeel

npx @aryaminus/controlkeel@latest

curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh
irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex
```

Tagged releases publish the packaged binaries, checksum manifest, installer scripts, and the portable plugin bundles described below.
If npmjs is unavailable for a specific environment, GitHub Packages remains a fallback path and requires scoped registry config and a token.

## Support by mechanism

The typed catalog in [support-matrix.md](support-matrix.md) is the code-aligned source of truth, but product readers often want the simpler answer first: **how does ControlKeel reach the tool?**

The same mechanism view is also the current project-rescue story. When a generator already changed the repo and there is no native attach path, ControlKeel still governs the work through bootstrap, findings, proofs, budgets, and proxy compatibility where available.

Today there are five support mechanisms:

- **Native attach**: MCP plus native skills, client config, and companion installs
- **Proxy-compatible**: governed OpenAI- or Anthropic-style traffic through ControlKeel
- **Runtime export**: headless runtime bundles for systems such as Devin and Open SWE
- **Provider-only**: CK-owned or local backend profiles such as Ollama, vLLM, SGLang, LM Studio, Hugging Face, and Codestral-compatible endpoints
- **Fallback governance**: bootstrap the repo, then use `controlkeel watch`, `controlkeel findings`, proofs, budgets, and `ck_validate` after an unsupported tool makes changes

This mechanism view is intentionally simpler than the typed support inventory, but it should never contradict it.

## Bidirectional execution model

ControlKeel now models each integration in both directions:

- **How the agent uses CK**: `local_mcp`, `hosted_mcp`, `a2a`, `plugin`, `native_skills`, `rules`, `workflows`, `hooks`, or `proxy`
- **How CK runs the agent**: `embedded`, `handoff`, `runtime`, or `none`
- **How much autonomy is truthful**: `direct`, `handoff`, `runtime`, or `inbound_only`

The practical meaning of those classes is:

- **direct**: ControlKeel can launch a locally verifiable command surface and keep the run policy-gated
- **handoff**: ControlKeel prepares a governed package, scoped credentials, and native/plugin bundle, then waits for the external client to continue
- **runtime**: ControlKeel talks to a remote or headless runtime and tracks the governed run through the same task-run primitives
- **inbound_only**: the agent can use ControlKeel, but CK does not currently drive that agent

Human intervention is only removed where the surface is truthful. Blocked findings and explicit approval constraints still stop all modes.

## Protocol interop and discovery

There are now three protocol surfaces around the catalog itself:

- **Local stdio MCP** for repo-local trust and native attach flows
- **Hosted MCP** for service-account-driven remote clients
- **Minimal A2A** for agent-card discovery and thin JSON-RPC message dispatch

Hosted MCP uses:

- `POST /mcp`
- `GET /.well-known/oauth-protected-resource/mcp`
- `GET /.well-known/oauth-protected-resource`
- `GET /.well-known/oauth-authorization-server`
- `POST /oauth/token`

Hosted access is intentionally narrow:

- local stdio MCP remains unauthenticated
- hosted MCP uses short-lived bearer tokens minted from workspace service accounts
- service-account create/list responses expose the derived `oauth_client_id`
- no browser OAuth flow or dynamic client registration in v1

Minimal A2A uses:

- `GET /.well-known/agent-card.json`
- `GET /.well-known/agent.json`
- `POST /a2a`

It advertises exactly the current governed capabilities:

- `ck_context`
- `ck_validate`
- `ck_finding`
- `ck_budget`
- `ck_route`
- `ck_delegate`

No second orchestration system is implied here. The A2A layer is only a thin facade over existing ControlKeel tools.

ACP registry support is also deliberately narrow:

- `controlkeel registry sync acp`
- `controlkeel registry status acp`

The remote registry only enriches existing rows with freshness, version, and homepage metadata in `/skills` and `GET /api/v1/skills/targets`. It never creates attach targets or overrides the built-in catalog.

## Provider-bridge supported agents

These are the strongest zero-setup paths today because ControlKeel can reuse a compatible provider environment from the attached client.

| Agent | Attach command | Bridge | Native companion | Exportable bundles |
|---|---|---|---|---|
| Claude Code | `controlkeel attach claude-code` | Anthropic-compatible environment | Installs `.claude/skills` and `.claude/agents` | `claude-standalone`, `claude-plugin` |
| Codex CLI | `controlkeel attach codex-cli` | OpenAI-compatible environment | Installs `.agents/skills` and `.codex/agents` | `codex`, `codex-plugin`, `open-standard` |
| Hermes Agent | `controlkeel attach hermes-agent` | Config-reference bridge from Hermes config | Installs `.hermes/skills` and `.hermes/mcp.json` | `hermes-native` |
| OpenClaw | `controlkeel attach openclaw` | Config-reference bridge from OpenClaw settings | Installs workspace or managed skills and emits OpenClaw config | `openclaw-native`, `openclaw-plugin` |
| Factory Droid | `controlkeel attach droid` | Gateway/base-URL bridge from Factory settings | Installs `.factory/skills`, `.factory/droids`, `.factory/commands`, `.factory/mcp.json` | `droid-bundle` |
| Forge | `controlkeel attach forge` | ACP session bridge when exposed by the client | ACP companion plus MCP fallback files | `forge-acp`, `instructions-only` |

## Native-first and repo-native agents

These clients get MCP plus a native companion install by default when you run `controlkeel attach ...`.
On a clean repo, `attach` also auto-bootstraps the governed project binding by default.

| Agent | Attach command | Native companion | Exportable bundles |
|---|---|---|---|
| Cline | `controlkeel attach cline` | Writes `.cline/skills`, `.clinerules`, `AGENTS.md`, and updates Cline MCP settings | `cline-native` |
| Cursor | `controlkeel attach cursor` | Writes `.agents/skills`, `.cursor/rules`, and `.cursor/mcp.json` | `cursor-native`, `instructions-only` |
| Windsurf | `controlkeel attach windsurf` | Writes `.agents/skills`, `.windsurf/rules`, and `.windsurf/mcp.json` | `windsurf-native`, `instructions-only` |
| Continue | `controlkeel attach continue` | Writes `.continue/prompts`, `.continue/mcp.json`, and governed guidance bundle | `continue-native`, `instructions-only` |
| Roo Code | `controlkeel attach roo-code` | Writes `.roo/skills`, `.roo/rules`, `.roo/commands`, `.roo/guidance`, `.roomodes`, `AGENTS.md`, and `.mcp.json` | `roo-native` |
| Goose | `controlkeel attach goose` | Writes `.goosehints`, `goose/workflow_recipes`, `AGENTS.md`, and registers a Goose MCP extension in `~/.config/goose/config.yaml` | `goose-native` |
| VS Code | `controlkeel attach vscode` | Writes `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` | `github-repo`, `copilot-plugin` |
| GitHub Copilot / Copilot CLI | `controlkeel attach copilot` | Writes `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` | `github-repo`, `copilot-plugin` |
| OpenCode | `controlkeel attach opencode` | Writes `.opencode/plugins`, `.opencode/agents`, `.opencode/commands`, `.opencode/mcp.json`, `AGENTS.md` | `opencode-native`, `instructions-only` |
| mcptocli | Manual setup | Wraps CK MCP as CLI; see [mcptocli integration](#mcptocli-cli-integration) | N/A |
| Kiro | `controlkeel attach kiro` | Writes `.kiro/hooks`, `.kiro/steering`, `.kiro/mcp.json`, `AGENTS.md` | `kiro-native`, `instructions-only` |
| Amp | `controlkeel attach amp` | Writes `.amp/plugins/controlkeel-governance.ts`, `.mcp.json`, `AGENTS.md` | `amp-native`, `instructions-only` |
| Gemini CLI | `controlkeel attach gemini-cli` | Writes `gemini-extension.json`, `.gemini/commands`, `skills/`, `GEMINI.md` | `gemini-cli-native`, `instructions-only` |

## mcptocli CLI integration

[mcptocli](https://github.com/MaximeRivest/mcptocli) is a tool that wraps any MCP server as a CLI command. While ControlKeel's native OpenCode integration is the recommended approach, mcptocli can be used as an alternative CLI interface.

### Installation

```bash
# macOS/Linux
curl -fsSL https://raw.githubusercontent.com/MaximeRivest/mcptocli/main/install.sh | sh

# Windows
irm https://raw.githubusercontent.com/MaximeRivest/mcptocli/main/install.ps1 | iex
```

### Setup with ControlKeel

Create a wrapper script to suppress debug output:

```bash
#!/bin/bash
cd /path/to/your/project
exec elixir --erl "-logger level error" -S mix ck.mcp --project-root /path/to/your/project
```

Then register with mcptocli:

```bash
mcptocli add controlkeel '/path/to/your/wrapper-script.sh'
```

### Usage

```bash
# List available tools
mcptocli controlkeel tools

# Run validation
mcptocli controlkeel ck_validate --scope full

# Check budget
mcptocli controlkeel ck_budget

# Interactive shell
mcptocli controlkeel shell
```

### Note

The native `controlkeel attach opencode` integration provides a deeper integration with OpenCode's plugin system, skill loading, and event hooks. mcptocli is useful if you want a simple CLI wrapper around the MCP tools without the full OpenCode integration.

## MCP plus instructions agents

These clients still attach through MCP, but the governed companion is an instructions bundle under `controlkeel/dist/instructions-only`.

| Agent | Attach command |
|---|---|
| Aider | `controlkeel attach aider` |

## Headless runtimes and typed non-attach surfaces

These appear in the same integration catalog, but they are intentionally **not** fake `attach` commands.

| Support class | Canonical ids | How ControlKeel supports them |
|---|---|---|
| Headless runtime | `devin`, `open-swe` | `controlkeel runtime export devin` and `controlkeel runtime export open-swe` write repo/runtime bundle files (`AGENTS.md`, MCP or webhook recipes, CI guidance). |
| Framework adapter | `dspy`, `gepa`, `deepagents`, `fastmcp` | Exposed through benchmark, policy-training, runtime-harness adapter exports, or generic MCP interoperability scaffolds. |
| Provider-only | `codestral`, `ollama-runtime`, `vllm`, `sglang`, `lmstudio`, `huggingface` | Exposed through CK provider/profile templates and OpenAI-compatible backend guidance. |
| Alias | `claude-dispatch`, `cognition`, `cursor-agent`, `codex-app-server`, `copilot-cli`, `t3code` | Resolve to canonical shipped targets rather than creating duplicate attach flows. |
| Unverified | `rlm-agent`, `slate`, `retune` | Kept visible as research names, but not over-promised as shipped support. |

Headless runtimes and remote clients can combine these with the hosted protocol layer above rather than relying on repo-local stdio MCP.

## Governed execution surfaces

ControlKeel can now drive agents as well as serve them:

- `controlkeel agents doctor`
- `controlkeel run task <id> [--agent auto|<id>] [--mode auto|embedded|handoff|runtime]`
- `controlkeel run session <id> [--agent auto|<id>]`
- `GET /api/v1/agents`
- `POST /api/v1/tasks/:id/run`
- `POST /api/v1/sessions/:id/run`
- `ck_delegate` over hosted MCP or A2A when the caller has `delegate:run`

Execution stays policy-gated:

- **direct** paths only run when a documented or locally configured command surface exists
- **handoff** paths emit the right native/plugin bundle, scoped credentials, and task package, then wait for continuation
- **runtime** paths create governed remote run packages and track remote refs
- blocked findings and explicit approval constraints pause the run instead of being bypassed

## Proxy-compatible clients

ControlKeel also exposes governed proxy endpoints for OpenAI-style and Anthropic-style traffic. This is useful for tools that can point directly at those APIs, but it is a different support tier from a native attach target or documented provider bridge.

Treat proxy support as **API-shape compatibility**, not as proof of a full native integration. Third-party web IDEs (Bolt, Lovable, Replit, v0, etc.) only work here if you can configure their outbound model URL to hit **your** ControlKeel base URL with the paths below—most products use their own hosted models, so test before claiming support.

### Proxy: what works today

Replace `{base}` with your ControlKeel server origin (for example `http://localhost:4000` in dev) and `{proxy_token}` with the session’s `proxy_token` (shown in Mission Control as full proxy URLs).

| Upstream shape | HTTP method and path on ControlKeel |
|----------------|-------------------------------------|
| OpenAI Responses API | `POST {base}/proxy/openai/{proxy_token}/v1/responses` |
| OpenAI Chat Completions | `POST {base}/proxy/openai/{proxy_token}/v1/chat/completions` |
| OpenAI Completions | `POST {base}/proxy/openai/{proxy_token}/v1/completions` |
| OpenAI Embeddings | `POST {base}/proxy/openai/{proxy_token}/v1/embeddings` |
| OpenAI Models | `GET {base}/proxy/openai/{proxy_token}/v1/models` |
| Anthropic Messages | `POST {base}/proxy/anthropic/{proxy_token}/v1/messages` |
| OpenAI Realtime (WebSocket) | `GET {base}/proxy/openai/{proxy_token}/v1/realtime` (scheme becomes `ws` / `wss` in Mission Control) |

Mission Control lists the resolved URLs for the current mission under **Proxy** (built with `ControlKeel.Proxy.url/3`). The governor runs the same validation stack as other governed paths before forwarding to OpenAI or Anthropic upstream.

Today that means:

- OpenAI-style `responses`, `chat/completions`, legacy `completions`, `embeddings`, and `models`
- Anthropic-style `messages`
- OpenAI realtime websocket path
- Better compatibility with external clients that probe `/v1/models` before use or rely on `embeddings` for retrieval workflows

## Unsupported and partially supported tools

ControlKeel does not need a fictional filesystem-watcher mode to be useful with unsupported tools.

The current fallback path is:

1. bootstrap a governed project
2. let the external tool make changes in the repo
3. use `controlkeel watch` for live findings and budget state
4. use `controlkeel findings`, proofs, and `ck_validate` for post-hoc governance
5. use governed proxy mode when the tool can point at OpenAI- or Anthropic-compatible endpoints

That keeps the support story honest: not every tool gets a first-class attach command, but unsupported tools can still participate in the governance loop.


Attach flag behavior:

- `--mcp-only` keeps attachment to MCP only
- `--no-native` skips native skills or bundle generation
- `--scope user|project` applies to targets that support both install locations

## Provider access

ControlKeel does not assume it can use an opaque agent subscription. Provider access resolves in this order:

1. supported agent bridge
2. workspace or service-account profile
3. user default provider profile
4. project override
5. local Ollama
6. heuristic fallback

Today, the documented bridge path is environment-based for supported clients:

- Claude Code -> Anthropic-compatible environment
- Codex CLI -> OpenAI-compatible environment

Some native-first clients are still CK-owned for provider access even when the attach flow is first-class:

- Cline -> native MCP + skills + `.clinerules`, but CK does not reuse Cline's encrypted provider secrets

OpenAI-compatible backends are supported through the CK `openai` provider path with a custom `base_url` and `model`, rather than through fake attach targets:

- vLLM
- SGLang
- LM Studio
- Hugging Face Inference Providers
- Codestral / Mistral-compatible endpoints

Example setup:

```bash
controlkeel provider set-base-url openai --value http://127.0.0.1:1234
controlkeel provider set-model openai --value local-model
controlkeel provider default openai
```

For Hugging Face or other hosted OpenAI-compatible backends that require a token:

```bash
controlkeel provider set-key openai --value "$HF_TOKEN"
controlkeel provider set-base-url openai --value https://router.huggingface.co
controlkeel provider set-model openai --value meta-llama/Llama-3.1-8B-Instruct:cerebras
controlkeel provider default openai
```

CK accepts base URLs with or without a trailing `/v1`.

If no bridge, CK-owned profile, or local model is available, agents can still use ControlKeel for governance, MCP tools, proofs, skills, and benchmarks without human setup. Model-backed features fall back to heuristics or return explicit capability guidance.

Practical rules:

- agent install location can be user- or project-scoped depending on target
- governed repo bootstrap remains project-local so each repository keeps its own proof trail and runtime wrapper
- heuristic mode is first-class for governance, not a broken state

## Operating modes

The product also has three practical operating lanes today:

- **Local packaged mode**: shipped today, local defaults, SQLite-backed, Ollama- or heuristic-capable, and designed to be a real end-user lane
- **Cloud/headless mode**: partial today, with service accounts, policy sets, webhooks, and runtime abstractions already in place
- **Team / enterprise mode**: a later branch, tracked separately from the current shipped local and headless slices

This means the local single-binary path is real product surface area, not just a developer bootstrap path. Cloud and team stories should be described conservatively until the remaining roadmap branches are complete.

## Skills and plugin commands

List and validate the skill catalog:

```bash
controlkeel skills list
controlkeel skills validate
controlkeel skills doctor
```

Export publishable bundles:

```bash
controlkeel plugin export codex
controlkeel plugin export claude
controlkeel plugin export copilot
controlkeel plugin export openclaw
controlkeel skills export --target claude-plugin
controlkeel skills export --target codex-plugin
controlkeel skills export --target cline-native
controlkeel skills export --target cursor-native
controlkeel skills export --target windsurf-native
controlkeel skills export --target continue-native
controlkeel skills export --target roo-native
controlkeel skills export --target goose-native
controlkeel skills export --target opencode-native
controlkeel skills export --target kiro-native
controlkeel skills export --target amp-native
controlkeel skills export --target gemini-cli-native
controlkeel skills export --target copilot-plugin
controlkeel skills export --target codex
controlkeel skills export --target provider-profile
controlkeel skills export --target open-standard
controlkeel runtime export devin
controlkeel runtime export open-swe
```

Install a native target without using `attach`:

```bash
controlkeel plugin install codex --scope project --mode hosted
controlkeel plugin install claude --scope user --mode local
controlkeel plugin install copilot --scope project --mode local
controlkeel skills install --target claude-standalone --scope user
controlkeel skills install --target cline-native --scope project
controlkeel skills install --target cursor-native --scope project
controlkeel skills install --target windsurf-native --scope project
controlkeel skills install --target continue-native --scope project
controlkeel skills install --target roo-native --scope project
controlkeel skills install --target goose-native --scope project
controlkeel skills install --target codex --scope user
controlkeel skills install --target github-repo --scope project
```

## Dist output locations

Exported bundles are written under:

- `controlkeel/dist/claude-plugin/`
- `controlkeel/dist/codex-plugin/`
- `controlkeel/dist/cline-native/`
- `controlkeel/dist/cursor-native/`
- `controlkeel/dist/windsurf-native/`
- `controlkeel/dist/continue-native/`
- `controlkeel/dist/roo-native/`
- `controlkeel/dist/goose-native/`
- `controlkeel/dist/opencode-native/`
- `controlkeel/dist/kiro-native/`
- `controlkeel/dist/amp-native/`
- `controlkeel/dist/gemini-cli-native/`
- `controlkeel/dist/copilot-plugin/`
- `controlkeel/dist/openclaw-plugin/`
- `controlkeel/dist/codex/`
- `controlkeel/dist/devin-runtime/`
- `controlkeel/dist/provider-profile/`
- `controlkeel/dist/open-standard/`
- `controlkeel/dist/instructions-only/`

Published release bundles use the same target set, but ship as release assets:

- `controlkeel-claude-plugin.tar.gz`
- `controlkeel-codex-plugin.tar.gz`
- `controlkeel-cline-native.tar.gz`
- `controlkeel-cursor-native.tar.gz`
- `controlkeel-windsurf-native.tar.gz`
- `controlkeel-continue-native.tar.gz`
- `controlkeel-roo-native.tar.gz`
- `controlkeel-goose-native.tar.gz`
- `controlkeel-copilot-plugin.tar.gz`
- `controlkeel-openclaw-plugin.tar.gz`
- `controlkeel-codex.tar.gz`
- `controlkeel-devin-runtime.tar.gz`
- `controlkeel-provider-profile.tar.gz`
- `controlkeel-open-standard.tar.gz`
- `controlkeel-instructions-only.tar.gz`

## MCP tool surface

Core runtime tools:

- `ck_validate`
- `ck_context`
- `ck_finding`
- `ck_budget`
- `ck_route`
- `ck_delegate`

Skill discovery tools are exposed when the catalog is not empty:

- `ck_skill_list`
- `ck_skill_load`

Skill loading is target-aware. `ck_skill_list` and `ck_skill_load` can take `target`, and when omitted ControlKeel derives the best family from the auth context, attached agent, or executor.

## Canonical source of truth

- Built-in skills live in `priv/skills/`
- Generated native bundles are derived from that catalog
- `/skills` in the web UI shows validation diagnostics, export/install actions, and the live compatibility matrix
