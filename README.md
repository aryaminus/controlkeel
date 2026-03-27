# ControlKeel

[![CI](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml)
[![Release](https://github.com/aryaminus/controlkeel/actions/workflows/release.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/release.yml)

ControlKeel is the control plane that turns AI coding into production engineering. It governs agent work across intent compilation, task planning, routing, validation, proof generation, typed memory, benchmarks, learned policy artifacts, and cross-agent skills distribution.

It sits above Claude Code, Codex, Cline, OpenCode, Cursor, Windsurf, Continue, Aider, Copilot / VS Code, and other agent clients. It can expose MCP tools, attach native skills where supported, export plugin bundles, proxy provider traffic, and persist the evidence trail for everything it governs.

## Quick start

### Install

```bash
# macOS / Linux
brew tap aryaminus/controlkeel && brew install controlkeel

# npm bootstrap
npm i -g @aryaminus/controlkeel

# GitHub Packages npm registry
echo "@aryaminus:registry=https://npm.pkg.github.com" >> ~/.npmrc
echo "//npm.pkg.github.com/:_authToken=YOUR_GITHUB_CLASSIC_PAT" >> ~/.npmrc
npm i -g @aryaminus/controlkeel --registry=https://npm.pkg.github.com

# Direct installers
curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh
irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex
```

GitHub Releases remain the canonical source for packaged binaries, checksums, and publishable plugin bundles.
GitHub Packages is also published for the npm bootstrap installer. Local auth to `npm.pkg.github.com` requires a GitHub personal access token (classic) with package scope; the release workflow publishes there using the repository `GITHUB_TOKEN`.

### Packaged binary

```bash
# 1. Start the local app
controlkeel

# 2. Change into the project you want to govern
cd /path/to/your/project

# 3. Attach your preferred client
#    ControlKeel will auto-bootstrap on first use.
#    OpenCode is the fastest MCP-plus-instructions path.
controlkeel attach opencode

# Optional explicit bootstrap / init
controlkeel bootstrap
controlkeel init

# 4. Trigger a known-bad change and inspect the result
controlkeel findings
controlkeel status
```

### Source checkout

```bash
git clone <repo>
cd controlkeel
mix setup
mix phx.server

# In the governed project
mix ck.attach opencode
mix ck.findings

# Optional explicit bootstrap / init
mix ck.init
```

More walkthroughs:

- [Getting started](docs/getting-started.md)
- [Agent integrations](docs/agent-integrations.md)
- [Support matrix (agents, MCP, skills)](docs/support-matrix.md)
- [Autonomy and findings](docs/autonomy-and-findings.md)
- [Benchmarks](docs/benchmarks.md)
- [Demo script](docs/demo-script.md)

## What the product includes

- Live onboarding and intent compilation at `/start`
- Mission control, findings browser, proof browser, policy studio, ship dashboard, and benchmark matrix
- MCP runtime with routing, validation, findings, budget, and skills tools
- FastPath scanner, Semgrep escalation, policy packs, and governed proxy paths
- Typed memory, immutable proof bundles, pause/resume checkpoints, and retrieval
- Benchmark engine, policy training pipeline, and learned router / budget-hint artifacts
- Native agent skills, plugin bundles, and MCP fallback instructions generated from `priv/skills/`

## Supported agent connections

ControlKeel now uses a **typed integration catalog**:

- `attach_client` for real `controlkeel attach <id>` targets
- `headless_runtime` for exported runtime bundles such as Devin and Open SWE
- `framework_adapter` for benchmark / policy / runtime harness adapters
- `provider_only` for provider/profile templates such as Codestral, vLLM, SGLang, LM Studio, Hugging Face, and Ollama
- `alias` for names that resolve to a canonical shipped target

### Provider-bridge supported

These have the strongest zero-setup provider story today because ControlKeel can borrow a compatible provider environment from the attached client.

| Agent | Attach command | Bridge | Companion output |
|---|---|---|---|
| Claude Code | `controlkeel attach claude-code` | Anthropic-compatible env | `.claude/skills`, `.claude/agents`, optional Claude plugin bundle |
| Codex CLI | `controlkeel attach codex-cli` | OpenAI-compatible env | `.agents/skills`, `.codex/agents` |
| Hermes Agent | `controlkeel attach hermes-agent` | Config-reference bridge from Hermes provider config | `.hermes/skills`, `.hermes/mcp.json`, `AGENTS.md` |
| OpenClaw | `controlkeel attach openclaw` | Config-reference bridge from OpenClaw settings | `skills/`, `.openclaw/openclaw.json`, plugin bundle |
| Factory Droid | `controlkeel attach droid` | Gateway / base-URL bridge from Factory settings | `.factory/skills`, `.factory/droids`, `.factory/commands`, `.factory/mcp.json` |
| Forge | `controlkeel attach forge` | ACP session bridge when the client exposes one | ACP companion bundle plus MCP fallback |

### Native-first and repo-native attachments

These get MCP plus a native companion install by default.

| Agent | Attach command | Companion output |
|---|---|---|
| Cline | `controlkeel attach cline` | `.cline/skills`, `.clinerules/`, `AGENTS.md`, plus Cline MCP config under `~/.cline/data/settings/` |
| VS Code | `controlkeel attach vscode` | `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` |
| GitHub Copilot / Copilot CLI | `controlkeel attach copilot` | `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` |

### MCP plus generated instruction bundles

OpenCode is the recommended quick-start path in this category.

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

### Proxy-compatible clients

ControlKeel's governed proxy currently exposes OpenAI-style and Anthropic-style paths. That makes it a good fit for tools that can point at those APIs directly, but it is not the same thing as a native bridge or first-class attach target.

`/skills` in the web app and [docs/agent-integrations.md](docs/agent-integrations.md) show the live compatibility matrix and export/install targets.

### Headless runtimes, framework adapters, and provider-only entries

- Devin / Cognition: `controlkeel runtime export devin`
- Open SWE: `controlkeel runtime export open-swe`
- DSPy, GEPA, DeepAgents, FastMCP: surfaced as framework adapters or protocol/tooling entries, not fake attach commands
- Codestral, vLLM, SGLang, LM Studio, Hugging Face, and Ollama: surfaced as provider/profile templates, not fake attach commands
- Aliases such as `cognition`, `codex-app-server`, `claude-dispatch`, `cursor-agent`, `copilot-cli`, and `t3code` point to their canonical shipped targets in the support matrix

Attach flags:

- `--mcp-only` disables all native companion generation
- `--no-native` keeps the MCP registration but skips native installs
- `--scope user|project` selects the install location when the target supports both

## Provider access and no-key mode

ControlKeel resolves model access in this order:

1. agent bridge when the attached client exposes a compatible provider environment
2. workspace or service-account profile
3. user default provider profile
4. project override
5. local Ollama
6. heuristic / no-LLM fallback

Configure provider profiles with:

```bash
controlkeel provider list
controlkeel provider show
controlkeel provider set-key openai --value "$OPENAI_API_KEY"
controlkeel provider set-base-url openai --value http://127.0.0.1:1234
controlkeel provider set-model openai --value local-model
controlkeel provider default openai
controlkeel provider doctor
```

If no keys and no local model are available, ControlKeel still runs governance, MCP, proofs, skills, and benchmark flows in degraded mode. Only true model-backed features fall back to heuristics or return explicit capability guidance.

Practical setup guidance:

- If you use Claude Code or Codex CLI, try the attached bridge path first.
- If you use Cline, its MCP + skills path is first-class, but CK still needs its own provider profile or local Ollama for CK-internal model work because Cline stores provider secrets separately.
- If you use vLLM, SGLang, LM Studio, Hugging Face, or Codestral-compatible endpoints, configure them through the CK `openai` provider with a custom `base_url` and `model`.
- If you use OpenCode or another MCP-plus-instructions client, the next best path is a CK-owned provider profile or local Ollama.
- Governed bindings remain project-local even when the agent install itself supports user scope.
- Heuristic mode is still useful for validation, findings, proofs, benchmarks, and skills when no model access is available.

## Skills, plugins, and exports

Built-in skills are canonical in `priv/skills/`. The same catalog can be:

- loaded through MCP with `ck_skill_list` and `ck_skill_load`
- installed natively with `controlkeel skills install`
- exported as plugin or portable bundles with `controlkeel skills export`

Targets:

- `codex`
- `claude-standalone`
- `claude-plugin`
- `cline-native`
- `copilot-plugin`
- `devin-runtime`
- `github-repo`
- `provider-profile`
- `open-standard`
- `instructions-only`

Examples:

```bash
controlkeel skills list
controlkeel skills validate
controlkeel skills doctor
controlkeel skills export --target claude-plugin
controlkeel skills export --target copilot-plugin
controlkeel skills install --target codex --scope user
```

Exported bundles are written under `controlkeel/dist/<target>/`.

Tagged releases also publish:

- platform binaries and Homebrew-friendly archives
- `controlkeel-checksums.txt`
- `install.sh` and `install.ps1`
- GitHub Packages npm bootstrap publication for `@aryaminus/controlkeel`
- `controlkeel-claude-plugin.tar.gz`
- `controlkeel-copilot-plugin.tar.gz`
- `controlkeel-codex.tar.gz`
- `controlkeel-open-standard.tar.gz`
- `controlkeel-instructions-only.tar.gz`

## Web UI

| Route | Purpose |
|---|---|
| `/start` | onboarding, interview, and execution brief compilation |
| `/missions/:id` | mission control, findings, proofs, memory hits, pause/resume |
| `/findings` | cross-session findings browser with guided auto-fix |
| `/proofs` | immutable proof bundles and details |
| `/benchmarks` | suite browser, run matrix, policy training surfaces |
| `/benchmarks/policies/:id` | learned policy artifact details and promotion state |
| `/policies` | policy packs and governance rules |
| `/skills` | skills studio, compatibility matrix, export/install actions |
| `/ship` | install funnel and session metrics |

## CLI

### Runtime binary

```bash
controlkeel
controlkeel serve
controlkeel init [options]
controlkeel bootstrap [--project-root /abs/path] [--ephemeral-ok]
controlkeel attach <agent>
controlkeel status
controlkeel provider list|show|default|set-key|doctor
controlkeel findings [--severity high] [--status open]
controlkeel approve <finding-id>
controlkeel proofs [--session-id ...] [--task-id ...]
controlkeel proof <task-id|proof-id>
controlkeel pause <task-id>
controlkeel resume <task-id>
controlkeel memory search "query"
controlkeel skills list|validate|export|install|doctor
controlkeel benchmark list|run|show|import|export
controlkeel policy list|train|show|promote|archive
controlkeel watch
controlkeel mcp [--project-root /abs/path]
controlkeel help
controlkeel version
```

### Source wrappers

Every runtime command also has a `mix ck.*` wrapper where it makes sense, including:

- `mix ck.init`
- `mix ck.attach`
- `mix ck.status`
- `mix ck.findings`
- `mix ck.approve`
- `mix ck.skills`
- `mix ck.benchmark`
- `mix ck.policy`
- `mix ck.mcp`
- `mix ck.demo`

## MCP runtime

Core MCP tools:

- `ck_validate`
- `ck_context`
- `ck_finding`
- `ck_budget`
- `ck_route`

Skills tools are exposed when the catalog is non-empty:

- `ck_skill_list`
- `ck_skill_load`

`controlkeel attach ...` is the preferred connection path. For direct stdio usage:

```bash
controlkeel mcp --project-root /absolute/path/to/project
```

## REST API

All endpoints return JSON.

### Sessions, tasks, proofs, memory

- `GET /api/v1/sessions`
- `POST /api/v1/sessions`
- `GET /api/v1/sessions/:id`
- `GET /api/v1/sessions/:id/audit-log`
- `POST /api/v1/sessions/:session_id/tasks`
- `PATCH /api/v1/tasks/:id`
- `POST /api/v1/tasks/:id/complete`
- `POST /api/v1/tasks/:id/pause`
- `POST /api/v1/tasks/:id/resume`
- `GET /api/v1/proofs`
- `GET /api/v1/proofs/:id`
- `GET /api/v1/proof/:task_id`
- `GET /api/v1/memory/search`
- `DELETE /api/v1/memory/:id`

### Validation, budgets, routing, findings

- `POST /api/v1/validate`
- `GET /api/v1/findings`
- `POST /api/v1/findings/:id/action`
- `GET /api/v1/budget`
- `POST /api/v1/route-agent`

### Skills

- `GET /api/v1/skills`
- `GET /api/v1/skills/:name`
- `GET /api/v1/skills/targets`
- `POST /api/v1/skills/export`
- `POST /api/v1/skills/install`

### Benchmarks and policy training

- `GET /api/v1/benchmarks`
- `POST /api/v1/benchmarks/runs`
- `GET /api/v1/benchmarks/runs/:id`
- `POST /api/v1/benchmarks/runs/:id/import`
- `GET /api/v1/benchmarks/runs/:id/export`
- `GET /api/v1/policies`
- `POST /api/v1/policies/train`
- `GET /api/v1/policies/:id`
- `POST /api/v1/policies/:id/promote`
- `POST /api/v1/policies/:id/archive`

## Configuration

Selected runtime environment variables:

```bash
# Server
PORT=4000
PHX_HOST=localhost

# Provider keys
ANTHROPIC_API_KEY=...
OPENAI_API_KEY=...
OPENROUTER_API_KEY=...
OLLAMA_HOST=http://localhost:11434

# Scanner / proxy
CONTROLKEEL_SEMGREP_BIN=semgrep
CONTROLKEEL_PROXY_OPENAI_UPSTREAM=https://api.openai.com
CONTROLKEEL_PROXY_ANTHROPIC_UPSTREAM=https://api.anthropic.com

# Intent compiler
CONTROLKEEL_INTENT_DEFAULT_PROVIDER=anthropic
CONTROLKEEL_INTENT_ANTHROPIC_MODEL=claude-sonnet-4-6
CONTROLKEEL_INTENT_OPENAI_MODEL=gpt-5.4

# Memory / embeddings
CONTROLKEEL_MEMORY_STORE=auto
CONTROLKEEL_EMBEDDINGS_PROVIDER=ollama
CONTROLKEEL_EMBEDDINGS_MODEL=nomic-embed-text

# Policy training
CONTROLKEEL_POLICY_TRAINING_PYTHON=python3
CONTROLKEEL_POLICY_TRAINING_TMP_DIR=/tmp
```

Packaged local mode also auto-derives `DATABASE_PATH` and `SECRET_KEY_BASE` when they are unset.

## Development

```bash
mix setup
mix phx.server
mix test
mix precommit
```

The app is Phoenix + Ecto on SQLite by default. Use the built-in `Req` client for HTTP work.

## Packaging

Single-binary builds use Burrito:

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release

BURRITO_TARGET=macos MIX_ENV=prod mix release
BURRITO_TARGET=macos_silicon MIX_ENV=prod mix release
BURRITO_TARGET=linux MIX_ENV=prod mix release
BURRITO_TARGET=windows MIX_ENV=prod mix release
```

Outputs land in `burrito_out/`.
