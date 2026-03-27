# ControlKeel Agent Integrations

This is the current ControlKeel distribution and attachment matrix.

**Canonical inventory:** [support-matrix.md](support-matrix.md) lists every `AgentIntegration.catalog/0` row, all MCP runtime tools, and `priv/skills/` bundles in one place. Use it when aligning docs with code.

## Install ControlKeel

ControlKeel itself is distributed through GitHub Releases, with convenience install channels layered on top:

```bash
brew tap aryaminus/controlkeel && brew install controlkeel
npm i -g @aryaminus/controlkeel
echo "@aryaminus:registry=https://npm.pkg.github.com" >> ~/.npmrc
echo "//npm.pkg.github.com/:_authToken=YOUR_GITHUB_CLASSIC_PAT" >> ~/.npmrc
npm i -g @aryaminus/controlkeel --registry=https://npm.pkg.github.com
curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh
irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex
```

Tagged releases publish the packaged binaries, checksum manifest, installer scripts, and the portable plugin bundles described below.
The GitHub Packages npm path is for the bootstrap installer only and requires a GitHub personal access token (classic) for local installs.

## Provider-bridge supported agents

These are the strongest zero-setup paths today because ControlKeel can reuse a compatible provider environment from the attached client.

| Agent | Attach command | Bridge | Native companion | Exportable bundles |
|---|---|---|---|---|
| Claude Code | `controlkeel attach claude-code` | Anthropic-compatible environment | Installs `.claude/skills` and `.claude/agents` | `claude-standalone`, `claude-plugin` |
| Codex CLI | `controlkeel attach codex-cli` | OpenAI-compatible environment | Installs `.agents/skills` and `.codex/agents` | `codex`, `open-standard` |
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
| VS Code | `controlkeel attach vscode` | Writes `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` | `github-repo`, `copilot-plugin` |
| GitHub Copilot / Copilot CLI | `controlkeel attach copilot` | Writes `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` | `github-repo`, `copilot-plugin` |

## MCP plus instructions agents

These clients still attach through MCP, but the native companion is an instructions bundle under `controlkeel/dist/instructions-only`. OpenCode is the recommended quick-start path in this class.

| Agent | Attach command |
|---|---|
| OpenCode | `controlkeel attach opencode` |
| Cursor | `controlkeel attach cursor` |
| Windsurf | `controlkeel attach windsurf` |
| Kiro | `controlkeel attach kiro` |
| Amp | `controlkeel attach amp` |
| Gemini CLI | `controlkeel attach gemini-cli` |
| Continue | `controlkeel attach continue` |
| Aider | `controlkeel attach aider` |

OpenCode notes:

- writes MCP configuration into the OpenCode config location
- exports the portable instruction bundle used by MCP-plus-instructions targets
- does not currently expose a documented provider bridge, so the best model-backed follow-up paths are a CK-owned provider profile or local Ollama

## Headless runtimes and typed non-attach surfaces

These appear in the same integration catalog, but they are intentionally **not** fake `attach` commands.

| Support class | Canonical ids | How ControlKeel supports them |
|---|---|---|
| Headless runtime | `devin`, `open-swe` | `controlkeel runtime export devin` and `controlkeel runtime export open-swe` write repo/runtime bundle files (`AGENTS.md`, MCP or webhook recipes, CI guidance). |
| Framework adapter | `dspy`, `gepa`, `deepagents`, `fastmcp` | Exposed through benchmark, policy-training, runtime-harness adapter exports, or generic MCP interoperability scaffolds. |
| Provider-only | `codestral`, `ollama-runtime`, `vllm`, `sglang`, `lmstudio`, `huggingface` | Exposed through CK provider/profile templates and OpenAI-compatible backend guidance. |
| Alias | `claude-dispatch`, `cognition`, `cursor-agent`, `codex-app-server`, `copilot-cli`, `t3code` | Resolve to canonical shipped targets rather than creating duplicate attach flows. |
| Unverified | `rlm-agent`, `slate`, `retune` | Kept visible as research names, but not over-promised as shipped support. |

## Proxy-compatible clients

ControlKeel also exposes governed proxy endpoints for OpenAI-style and Anthropic-style traffic. This is useful for tools that can point directly at those APIs, but it is a different support tier from a native attach target or documented provider bridge.

Treat proxy support as **API-shape compatibility**, not as proof of a full native integration. Third-party web IDEs (Bolt, Lovable, Replit, v0, etc.) only work here if you can configure their outbound model URL to hit **your** ControlKeel base URL with the paths below—most products use their own hosted models, so test before claiming support.

### Proxy: what works today

Replace `{base}` with your ControlKeel server origin (for example `http://localhost:4000` in dev) and `{proxy_token}` with the session’s `proxy_token` (shown in Mission Control as full proxy URLs).

| Upstream shape | HTTP method and path on ControlKeel |
|----------------|-------------------------------------|
| OpenAI Responses API | `POST {base}/proxy/openai/{proxy_token}/v1/responses` |
| OpenAI Chat Completions | `POST {base}/proxy/openai/{proxy_token}/v1/chat/completions` |
| Anthropic Messages | `POST {base}/proxy/anthropic/{proxy_token}/v1/messages` |
| OpenAI Realtime (WebSocket) | `GET {base}/proxy/openai/{proxy_token}/v1/realtime` (scheme becomes `ws` / `wss` in Mission Control) |

Mission Control lists the resolved URLs for the current mission under **Proxy** (built with `ControlKeel.Proxy.url/3`). The governor runs the same validation stack as other governed paths before forwarding to OpenAI or Anthropic upstream.

Today that means:

- OpenAI-style `responses` and `chat/completions`
- Anthropic-style `messages`
- OpenAI realtime websocket path


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

## Skills and plugin commands

List and validate the skill catalog:

```bash
controlkeel skills list
controlkeel skills validate
controlkeel skills doctor
```

Export publishable bundles:

```bash
controlkeel skills export --target claude-plugin
controlkeel skills export --target cline-native
controlkeel skills export --target copilot-plugin
controlkeel skills export --target codex
controlkeel skills export --target provider-profile
controlkeel skills export --target open-standard
controlkeel runtime export devin
controlkeel runtime export open-swe
```

Install a native target without using `attach`:

```bash
controlkeel skills install --target claude-standalone --scope user
controlkeel skills install --target cline-native --scope project
controlkeel skills install --target codex --scope user
controlkeel skills install --target github-repo --scope project
```

## Dist output locations

Exported bundles are written under:

- `controlkeel/dist/claude-plugin/`
- `controlkeel/dist/cline-native/`
- `controlkeel/dist/copilot-plugin/`
- `controlkeel/dist/codex/`
- `controlkeel/dist/devin-runtime/`
- `controlkeel/dist/provider-profile/`
- `controlkeel/dist/open-standard/`
- `controlkeel/dist/instructions-only/`

Published release bundles use the same target set, but ship as release assets:

- `controlkeel-claude-plugin.tar.gz`
- `controlkeel-cline-native.tar.gz`
- `controlkeel-copilot-plugin.tar.gz`
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

Skill discovery tools are exposed when the catalog is not empty:

- `ck_skill_list`
- `ck_skill_load`

## Canonical source of truth

- Built-in skills live in `priv/skills/`
- Generated native bundles are derived from that catalog
- `/skills` in the web UI shows validation diagnostics, export/install actions, and the live compatibility matrix
