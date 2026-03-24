# ControlKeel Agent Integrations

This is the current ControlKeel distribution and attachment matrix.

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

## Native-first and repo-native agents

These clients get MCP plus a native companion install by default when you run `controlkeel attach ...`.
On a clean repo, `attach` also auto-bootstraps the governed project binding by default.

| Agent | Attach command | Native companion | Exportable bundles |
|---|---|---|---|
| VS Code | `controlkeel attach vscode` | Writes `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` | `github-repo`, `copilot-plugin` |
| GitHub Copilot | `controlkeel attach copilot` | Writes `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` | `github-repo`, `copilot-plugin` |

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
controlkeel skills export --target copilot-plugin
controlkeel skills export --target codex
controlkeel skills export --target open-standard
```

Install a native target without using `attach`:

```bash
controlkeel skills install --target claude-standalone --scope user
controlkeel skills install --target codex --scope user
controlkeel skills install --target github-repo --scope project
```

## Dist output locations

Exported bundles are written under:

- `controlkeel/dist/claude-plugin/`
- `controlkeel/dist/copilot-plugin/`
- `controlkeel/dist/codex/`
- `controlkeel/dist/open-standard/`
- `controlkeel/dist/instructions-only/`

Published release bundles use the same target set, but ship as release assets:

- `controlkeel-claude-plugin.tar.gz`
- `controlkeel-copilot-plugin.tar.gz`
- `controlkeel-codex.tar.gz`
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
