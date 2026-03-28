# ControlKeel

[![CI](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml)
[![Release](https://github.com/aryaminus/controlkeel/actions/workflows/release.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/release.yml)

ControlKeel is the control tower that turns agent-generated work into secure, scoped, validated, production-ready delivery. ControlKeel turns agent output into production engineering. It governs agent work across intent compilation, task planning, routing, validation, proof generation, typed memory, benchmarks, learned policy artifacts, and cross-agent skills distribution.

It sits above Claude Code, Codex, Cline, OpenCode, Cursor, Windsurf, Continue, Aider, Copilot / VS Code, and other agent clients. It can expose MCP tools, attach native skills where supported, export plugin bundles, proxy provider traffic, and persist the evidence trail for everything it governs.

Agent output is cheap. Reviewability, security, release safety, and cost control are not. ControlKeel exists to govern that layer, not replace the coding model underneath it.

That is also why ControlKeel works as a project-rescue layer: when a generator leaves you with a brittle repo or an unclear launch boundary, bootstrap the governed project, make the constraints visible, and keep proof attached to the work.

The default wedge is serious solo builders and tiny agent-heavy teams first. Team / platform expansion exists, but the product story today is still governed autonomy for builders who already have agent output and need it turned into production-ready delivery.

ControlKeel is not:

- another IDE
- another coding model
- a prompt marketplace
- post-hoc code review only

The live control loop is:

- Mission Control for active task state, approvals, and blocked work
- Proof Browser for immutable audit artifacts and rollback guidance
- Ship Dashboard for outcome and readiness metrics
- Benchmarks for comparative evidence across governed runs

The other core differentiator is **occupation-first governance**. Users choose what best describes their work, and ControlKeel maps that to a domain pack, interview language, and compliance posture. The product is designed to talk about work and risk in plain language rather than forcing non-experts to begin with framework acronyms.

ControlKeel also now has a narrow hosted interop layer on top of the local runtime:

- local stdio MCP for repo-local trust and native attach flows
- hosted MCP at `POST /mcp` for service-account-driven headless clients
- a minimal A2A facade at `POST /a2a` plus well-known agent-card discovery
- ACP registry cache enrichment for discovery freshness without making a remote registry the source of truth

## Governed delivery lifecycle

ControlKeel is designed as one governed assembly line, not a collection of disconnected tools:

- **Intent intake** begins at `/start`, where the operator describes the work in plain language.
- **Execution brief** compilation turns that input into a scoped, production-minded plan.
- **Task graph and routing** direct the work into manageable task slices and recommended agent paths.
- **Validation and findings** apply FastPath, Semgrep, policy packs, and governed rulings before risky work passes.
- **Proof bundles** freeze immutable delivery evidence for completed tasks.
- **Ship Dashboard** shows stewardship evidence such as funnel speed, deploy-readiness, and risky intervention rate.
- **Benchmarks** provide comparative evidence across governed runs and subjects.

The stewardship surfaces in the product are `/ship` and `/benchmarks`. That is where ControlKeel proves that governed work is not only faster, but more reviewable and safer to ship.

## Repo Governance

ControlKeel now extends beyond runtime governance and into **repo-native delivery controls**:

- `controlkeel review diff --base <ref> --head <ref>` reviews added hunks before merge
- `controlkeel review pr --patch <file>|--stdin` reviews a prepared PR patch
- `controlkeel release-ready --session-id <id>|--sha <sha>` checks proof-backed release readiness
- `controlkeel govern install github` scaffolds cheap GitHub workflows for PR review, release checks, and Scorecards

These surfaces reuse the same FastPath, Semgrep, findings, proofs, budgets, and deploy-readiness logic that already powers Mission Control and the governed proxy. The goal is to govern code before merge and before release, not only while an agent is actively running.

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
- [Control-plane architecture](docs/control-plane-architecture.md)
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
| Roo Code | `controlkeel attach roo-code` | `.roo/skills`, `.roo/rules`, `.roo/commands`, `.roo/guidance`, `.roomodes`, `AGENTS.md`, `.mcp.json` |
| Goose | `controlkeel attach goose` | `.goosehints`, `goose/workflow_recipes`, `AGENTS.md`, plus Goose MCP extension config under `~/.config/goose/config.yaml` |
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

ACP registry freshness is optional but available:

```bash
controlkeel registry sync acp
controlkeel registry status acp
```

The cached registry only enriches shipped integration rows with freshness and homepage/version metadata. It never creates new attach targets or overrides the built-in catalog.

### Integration modes

Another useful way to understand ControlKeel support is by **mechanism**, not only by client name:

- **Native attach**: MCP plus native skills, client config, and companion bundle generation
- **Proxy-compatible**: governed OpenAI/Anthropic-style traffic for tools that can target those endpoints directly
- **Runtime export**: headless runtime bundles for tools like Devin and Open SWE
- **Provider-only**: CK-owned or local backend profiles such as Ollama, vLLM, SGLang, LM Studio, Hugging Face, and Codestral-compatible endpoints
- **Fallback governance**: if a tool is unsupported, bootstrap the project and use `controlkeel watch`, `controlkeel findings`, proofs, budgets, and `ck_validate` flows after the agent has made changes

That fallback path is the current rescue story for browser generators and partial integrations: ControlKeel does not claim native attach everywhere, but it can still govern the repo once it is bootstrapped.

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

## Operating modes

ControlKeel has three honest operating lanes today:

- **Local packaged mode**: shipped today, local defaults, SQLite-backed, and useful with either Ollama or heuristic/no-key governance paths
- **Cloud/headless mode**: partial today, with service accounts, policy sets, webhooks, provider profiles, and a cloud/runtime abstraction already in place
- **Team / enterprise mode**: still a later branch, tracked separately from the current shipped local and headless slices

This means the local single-binary path is a real product lane, not just a developer convenience. The cloud and team stories exist, but they should be described conservatively until the broader remaining-work branches are complete.

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
- `roo-native`
- `goose-native`
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
controlkeel provider list|show|default|set-key|set-base-url|set-model|doctor
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

That local stdio path stays friction-light and unauthenticated by design. Hosted remote access uses the separate protocol surfaces below.

## Hosted protocol interop

Hosted interop is intentionally narrow. It is meant for service-account-driven remote clients and machine integrations, not as a second orchestration engine.

### Hosted MCP

- `POST /mcp` serves stateless JSON-response MCP for `initialize`, `tools/list`, and `tools/call`
- `GET /mcp` and `DELETE /mcp` intentionally return `405`
- protected-resource and auth-server discovery live at:
  - `GET /.well-known/oauth-protected-resource/mcp`
  - `GET /.well-known/oauth-protected-resource`
  - `GET /.well-known/oauth-authorization-server`
- access tokens are minted by `POST /oauth/token` using the client-credentials grant

Local stdio MCP and hosted MCP are separate on purpose:

- local stdio MCP trusts the local machine
- hosted MCP requires bearer access tokens on every request
- hosted MCP uses workspace-scoped service accounts as confidential clients

### Service-account client credentials

Create or list a workspace service account through the CLI or API. Both surfaces return the derived OAuth client id so callers do not need to guess it:

```bash
controlkeel service-account create --workspace-id 1 --name "ci-mcp" --scopes "mcp:access context:read validate:run"
controlkeel service-account list --workspace-id 1
```

Then exchange that service account for a short-lived access token:

```bash
curl -X POST http://localhost:4000/oauth/token \
  -H "content-type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=ck-sa-123" \
  --data-urlencode "client_secret=YOUR_SERVICE_ACCOUNT_TOKEN" \
  --data-urlencode "resource=mcp" \
  --data-urlencode "scope=mcp:access context:read validate:run"
```

Hosted protocol scopes are explicit:

- `mcp:access`
- `a2a:access`
- `context:read`
- `validate:run`
- `finding:write`
- `budget:write`
- `route:read`
- `skills:read`

### Minimal A2A

ControlKeel also exposes a thin A2A facade:

- `GET /.well-known/agent-card.json`
- `GET /.well-known/agent.json`
- `POST /a2a`

This A2A surface is intentionally limited:

- `message/send` only
- no task store
- no push notifications
- no streaming session lifecycle

The advertised governed skills are:

- `ck_context`
- `ck_validate`
- `ck_finding`
- `ck_budget`
- `ck_route`

## REST API

All endpoints return JSON.

### Intent, domains, and assembled context

- `GET /api/v1/domains`
- `GET /api/v1/context`
- `POST /api/v1/context`

`/api/v1/context` returns the assembled mission context for operators and agents, including the derived production boundary summary from the execution brief.

### Sessions, tasks, proofs, and memory

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

### Workspace and headless controls

- `GET /api/v1/workspaces/:id/service-accounts`
- `POST /api/v1/workspaces/:id/service-accounts`
- `POST /api/v1/service-accounts/:id/rotate`
- `GET /api/v1/workspaces/:id/policy-sets`
- `POST /api/v1/workspaces/:id/policy-sets`
- `POST /api/v1/workspaces/:id/policy-sets/:policy_set_id/apply`
- `GET /api/v1/workspaces/:id/webhooks`
- `POST /api/v1/workspaces/:id/webhooks`
- `POST /api/v1/webhooks/:id/replay`

Service-account responses include `oauth_client_id` so headless MCP/A2A clients can use the client-credentials flow without deriving identifiers themselves.

### Validation, budgets, routing, findings

- `POST /api/v1/validate`
- `GET /api/v1/findings`
- `POST /api/v1/findings/:id/action`
- `GET /api/v1/budget`
- `POST /api/v1/route-agent`

### Repo governance

- `POST /api/v1/review/diff`
- `POST /api/v1/review/pr`
- `POST /api/v1/release/readiness`
- `POST /api/v1/governance/install/github`

### Skills

- `GET /api/v1/skills`
- `GET /api/v1/skills/:name`
- `GET /api/v1/skills/targets`
- `POST /api/v1/skills/export`
- `POST /api/v1/skills/install`

`GET /api/v1/skills/targets` includes optional ACP registry enrichment fields such as `registry_match`, `registry_version`, `registry_url`, and `registry_stale`, plus top-level `registry_status` for the cache itself.

## Protocol endpoints

- `POST /mcp`
- `GET /mcp`
- `DELETE /mcp`
- `GET /.well-known/oauth-protected-resource/mcp`
- `GET /.well-known/oauth-protected-resource`
- `GET /.well-known/oauth-authorization-server`
- `POST /oauth/token`
- `GET /.well-known/agent-card.json`
- `GET /.well-known/agent.json`
- `POST /a2a`

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
