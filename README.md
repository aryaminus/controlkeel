# ControlKeel

[![CI](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml)
[![Release](https://github.com/aryaminus/controlkeel/actions/workflows/release.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/release.yml)

ControlKeel is the control plane that turns AI coding into production engineering. It governs agent work across intent compilation, task planning, routing, validation, proof generation, typed memory, benchmarks, learned policy artifacts, and cross-agent skills distribution.

It sits above Claude Code, Codex, Cursor, Windsurf, Continue, Aider, Copilot / VS Code, and other agent clients. It can expose MCP tools, attach native skills where supported, export plugin bundles, proxy provider traffic, and persist the evidence trail for everything it governs.

## Quick start

### Install

```bash
# macOS / Linux
brew tap aryaminus/controlkeel && brew install controlkeel

# Cross-platform bootstrap
npm i -g @aryaminus/controlkeel

# Direct installers
curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh
irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex
```

GitHub Releases remain the canonical source for packaged binaries, checksums, and publishable plugin bundles.

### Packaged binary

```bash
# 1. Start the local app
controlkeel

# 2. Initialize a governed project
cd /path/to/your/project
controlkeel init

# 3. Attach your preferred client
controlkeel attach claude-code

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
mix ck.init
mix ck.attach claude-code
mix ck.findings
```

More walkthroughs:

- [Getting started](docs/getting-started.md)
- [Agent integrations](docs/agent-integrations.md)
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

### Native-first attachments

These get MCP plus a native companion install by default.

| Agent | Attach command | Companion output |
|---|---|---|
| Claude Code | `controlkeel attach claude-code` | `.claude/skills`, `.claude/agents`, optional Claude plugin bundle |
| Codex CLI | `controlkeel attach codex-cli` | `.agents/skills`, `.codex/agents` |
| VS Code | `controlkeel attach vscode` | `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` |
| GitHub Copilot | `controlkeel attach copilot` | `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` |

### MCP plus generated instruction bundles

| Agent | Attach command |
|---|---|
| Cursor | `controlkeel attach cursor` |
| Windsurf | `controlkeel attach windsurf` |
| Kiro | `controlkeel attach kiro` |
| Amp | `controlkeel attach amp` |
| OpenCode | `controlkeel attach opencode` |
| Gemini CLI | `controlkeel attach gemini-cli` |
| Continue | `controlkeel attach continue` |
| Aider | `controlkeel attach aider` |

`/skills` in the web app and [docs/agent-integrations.md](docs/agent-integrations.md) show the live compatibility matrix and export/install targets.

Attach flags:

- `--mcp-only` disables all native companion generation
- `--no-native` keeps the MCP registration but skips native installs
- `--scope user|project` selects the install location when the target supports both

## Skills, plugins, and exports

Built-in skills are canonical in `priv/skills/`. The same catalog can be:

- loaded through MCP with `ck_skill_list` and `ck_skill_load`
- installed natively with `controlkeel skills install`
- exported as plugin or portable bundles with `controlkeel skills export`

Targets:

- `codex`
- `claude-standalone`
- `claude-plugin`
- `copilot-plugin`
- `github-repo`
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
controlkeel attach <agent>
controlkeel status
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
