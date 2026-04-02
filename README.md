# ControlKeel

[![CI](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml)
[![Release Smoke](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml)
[![Latest Release](https://img.shields.io/github/v/release/aryaminus/controlkeel.svg)](https://github.com/aryaminus/controlkeel/releases/latest)
[![npm version](https://img.shields.io/npm/v/%40aryaminus/controlkeel.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel)

**ControlKeel is the cerebellum for agent-generated software delivery.** Just as the cerebellum constantly compares motor intent against sensory feedback — detecting drift before you stumble — ControlKeel sits between your coding agents and production, comparing *intended* delivery against *actual* delivery, catching governance drift before it ships.

It governs agent work across intent compilation, task planning, routing, validation, proof generation, typed memory, benchmarks, learned policy artifacts, and cross-agent skills distribution.

> Agent output is cheap. Reviewability, security, release safety, and cost control are not. ControlKeel governs that layer — it doesn't replace the coding model underneath.

## How it works

```text
┌─────────────────────────────────────────────────────────────┐
│                      Your Coding Agent                       │
│   Claude Code · Codex · Cursor · Windsurf · Cline · Aider   │
│   OpenCode · Kiro · Amp · Gemini CLI · Copilot · Goose ...  │
└──────────────────────────┬──────────────────────────────────┘
                           │  MCP · native skills · plugins
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      ControlKeel                             │
│                                                              │
│  Intent → Tasks → Route → Validate → Prove → Ship           │
│                                                              │
│  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌──────────────────┐  │
│  │ FastPath │ │ Semgrep  │ │ Budget │ │ Proof Bundles    │  │
│  │ Scanner  │ │ Policies │ │ Gates  │ │ Immutable Audit  │  │
│  └──────────┘ └──────────┘ └────────┘ └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### The governed lifecycle

1. **Intent intake** at `/start` — describe work in plain language
2. **Execution brief** — scoped, production-minded plan compiled from your intent
3. **Task graph & routing** — work sliced into tasks, routed to recommended agents
4. **Validation & findings** — FastPath, Semgrep, policy packs applied before risky work passes
5. **Proof bundles** — immutable delivery evidence frozen per task
6. **Ship Dashboard** — deploy-readiness, funnel speed, intervention rate

## Quick start

### Install

```bash
# Homebrew (macOS and Linux x86_64)
brew tap aryaminus/controlkeel && brew install controlkeel

# npm bootstrap (macOS x86_64/arm64, Linux x86_64, Windows x86_64)
npm i -g @aryaminus/controlkeel
# or: pnpm add -g @aryaminus/controlkeel
# or: yarn global add @aryaminus/controlkeel

# one-off run (no global install)
npx @aryaminus/controlkeel@latest

# Unix installer from the latest GitHub release
curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh

# Raw bootstrap script from this repo
curl -fsSL https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.sh | sh
```

```powershell
# Windows PowerShell installer
irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex

# Raw bootstrap script from this repo
irm https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.ps1 | iex
```

Supported packaged binaries today:

| Platform | Asset |
| --- | --- |
| macOS Apple Silicon | `controlkeel-macos-arm64` / `.tar.gz` |
| macOS Intel | `controlkeel-macos-x86_64` / `.tar.gz` |
| Linux arm64 | `controlkeel-linux-arm64` / `.tar.gz` |
| Linux x86_64 | `controlkeel-linux-x86_64` / `.tar.gz` |
| Windows x86_64 | `controlkeel-windows-x86_64.exe` / `.zip` |

`npm`, the raw installer scripts, and the release-hosted installer scripts all resolve to the same GitHub release binaries. If you need a platform outside that list, use source install for now.

### First run

```bash
# 1. Start ControlKeel
controlkeel

# 2. In your project directory, attach your agent
controlkeel attach claude-code   # or: opencode, cursor, cline, kiro, amp, ...

# 3. Inspect governance state
controlkeel findings
controlkeel status
```

### From source

```bash
git clone https://github.com/aryaminus/controlkeel && cd controlkeel
mix setup && mix phx.server

# In the governed project
mix ck.attach opencode
mix ck.findings
```

## Supported agents

### Choose your agent

- Hook-native: `claude-code`, `copilot`, `windsurf`, `cline`, `kiro`
- Plugin-native: `opencode`, `amp`
- File-plan-mode: `pi`
- Prompt/command-native: `continue`, `gemini-cli`, `goose`, `roo-code`
- Browser/embed companion: `vscode`
- Review-only: `codex-cli`, `aider`
- Broader native/governed matrix: see [docs/support-matrix.md](docs/support-matrix.md) and [docs/host-surface-parity.md](docs/host-surface-parity.md)
- Direct host installs: see [docs/direct-host-installs.md](docs/direct-host-installs.md)

### Host parity classes

| Host | Attach | Phase model | Review path | Browser embedding | Package outputs |
| --- | --- | --- | --- | --- | --- |
| Claude Code | `controlkeel attach claude-code` | `host_plan_mode` | native hook submits and waits on review | external | `controlkeel-claude-plugin.tar.gz` |
| GitHub Copilot | `controlkeel attach copilot` | `host_plan_mode` | hook and command review flow | external | `controlkeel-copilot-plugin.tar.gz` |
| OpenCode | `controlkeel attach opencode` | `host_plan_mode` | plugin tool submits plan review | external | `controlkeel-opencode-native.tar.gz`, `controlkeel-opencode-native.tgz` |
| Pi | `controlkeel attach pi` | `file_plan_mode` | plan-file submit plus browser approval | external | `controlkeel-pi-native.tar.gz`, `controlkeel-pi-native.tgz` |
| VS Code | `controlkeel attach vscode` | `review_only` | browser review in a companion webview | `vscode_webview` | `controlkeel-vscode-companion.vsix` |
| Codex CLI | `controlkeel attach codex-cli` | `review_only` | diff and completion review commands | none | `controlkeel-codex.tar.gz`, `controlkeel-codex-plugin.tar.gz` |

Expanded official surfaces now shipped for the broader matrix:

- Windsurf: Cascade hooks, workflows, commands, and MCP repo bundle
- Continue: prompts, slash-command style review prompts, headless guidance, and `.continue/mcpServers/controlkeel.yaml`
- Cline: rules, workflows, commands, hooks, and CLI MCP config companion
- Goose: repo hints, workflow recipes, commands, and Goose extension YAML
- Kiro: hooks, steering, tool-policy settings, commands, and MCP config
- Amp: TypeScript plugin, command docs, and plugin package scaffold
- Gemini CLI: extension manifest plus review and submit-plan commands
- Cursor: rules, commands, background-agent guidance, and MCP config
- Roo Code: rules, commands, cloud-agent guidance, and governed mode files
- Aider: `AIDER.md`, `.aider.conf.yml`, and command-driven review snippets

Each shipped host now publishes the same code-backed parity contract in `/skills`: install experience, review experience, phase model, browser embedding, subagent visibility, installed artifacts, and packaged outputs.

Runtime-backed hosts also publish runtime transport metadata. Today that means:

- Claude Code: `claude_agent_sdk`, host-owned Anthropic auth, hook/SDK review transport
- GitHub Copilot: `hook_session_parser`, host-owned auth, hook/session review transport
- OpenCode: `opencode_sdk`, host-owned provider auth, plugin/session review transport
- Pi: `pi_rpc`, host-owned provider auth, extension/RPC review transport
- VS Code: `vscode_companion`, workspace-owned embed surface, companion review transport
- Codex CLI: `codex_sdk`, host-owned OpenAI auth, command/thread review transport

### Direct host installs

Where the host supports it, CK now publishes or packages a direct-install surface in addition to `controlkeel attach`:

- OpenCode: add `"plugin": ["@aryaminus/controlkeel-opencode"]` to `opencode.json`
- Pi: `pi install npm:@aryaminus/controlkeel-pi-extension`
- Pi short form: `pi -e npm:@aryaminus/controlkeel-pi-extension`
- VS Code: `code --install-extension controlkeel-vscode-companion.vsix`
- Gemini CLI: `gemini extensions link ./controlkeel/dist/gemini-cli-native`
- Claude Code: `claude --plugin-dir ./controlkeel/dist/claude-plugin`
- Copilot: `controlkeel plugin install copilot`
- Codex CLI: `controlkeel plugin install codex`

Claude, Copilot, and Codex plugin bundles now all ship explicit review commands as well:

- `/controlkeel-review`
- `/controlkeel-annotate`
- `/controlkeel-last`

For the full host-by-host truth table, see [docs/direct-host-installs.md](docs/direct-host-installs.md).

### Attach targets (MCP + companion install)

| Agent | Attach | Integration class | Native surfaces |
| --- | --- | --- | --- |
| Claude Code | `attach claude-code` | Provider-bridge | `.claude/skills`, `.claude/agents`, plugin bundle |
| Codex CLI | `attach codex-cli` | Review-only | `.agents/skills`, `.codex/agents`, review commands |
| Hermes Agent | `attach hermes-agent` | Provider-bridge | `.hermes/skills`, `.hermes/mcp.json` |
| OpenClaw | `attach openclaw` | Provider-bridge | Workspace/managed skills and OpenClaw config |
| Factory Droid | `attach droid` | Provider-bridge | `.factory/skills`, `.factory/droids`, `.factory/commands` |
| Forge | `attach forge` | Provider-bridge | ACP companion + MCP fallback files |
| Cline | `attach cline` | Hook-native | `.cline/skills`, `.clinerules/`, `.cline/commands`, `.cline/hooks`, MCP config |
| Roo Code | `attach roo-code` | Prompt/command-native | `.roo/skills`, `.roo/rules`, `.roo/commands`, `.roo/guidance`, `.roomodes` |
| Cursor | `attach cursor` | Native-first | `.cursor/rules`, `.cursor/commands`, `.cursor/background-agents`, `.cursor/mcp.json` |
| Windsurf | `attach windsurf` | Hook-native | `.windsurf/rules`, `.windsurf/commands`, `.windsurf/workflows`, `.windsurf/hooks`, `.windsurf/mcp.json` |
| Continue | `attach continue` | Prompt/command-native | `.continue/prompts`, `.continue/commands`, `.continue/mcpServers/controlkeel.yaml`, `.continue/mcp.json` |
| Pi | `attach pi` | File-plan-mode | `.pi/controlkeel.json`, `.pi/commands`, `.pi/mcp.json`, `pi-extension.json`, `PI.md` |
| Copilot | `attach copilot` | Hook-native | `.github/skills`, `.github/agents`, `.github/commands`, `.vscode/mcp.json` |
| VS Code | `attach vscode` | Browser/embed companion | `.github/skills`, `.github/agents`, `.vscode/mcp.json`, `.vscode/extensions.json`, companion `.vsix` |
| Goose | `attach goose` | Prompt/command-native | `.goosehints`, workflow recipes, Goose commands, extension config |
| OpenCode | `attach opencode` | Plugin-native | `.opencode/plugins`, `.opencode/agents`, `.opencode/commands`, `package.json` |
| Gemini CLI | `attach gemini-cli` | Prompt/command-native | `gemini-extension.json`, `.gemini/commands/`, `skills/`, `GEMINI.md`, extension README |
| Kiro | `attach kiro` | Hook-native | `.kiro/hooks/`, `.kiro/steering/`, `.kiro/settings/`, `.kiro/commands/`, MCP config |
| Amp | `attach amp` | Plugin-native | `.amp/plugins/`, `.amp/commands/`, `.amp/package.json` |

### MCP + command-driven

| Agent | Attach |
| --- | --- |
| Aider | `attach aider` |

### Headless runtimes

| Agent | Command |
| --- | --- |
| Devin | `runtime export devin` |
| Open SWE | `runtime export open-swe` |

See [docs/agent-integrations.md](docs/agent-integrations.md) and [docs/support-matrix.md](docs/support-matrix.md) for the full compatibility matrix, provider bridges, proxy-compatible clients, framework adapters, and export targets.

## Web UI

| Route | Purpose |
| --- | --- |
| `/start` | Onboarding, interview, execution brief |
| `/missions/:id` | Mission control, findings, proofs, pause/resume |
| `/findings` | Cross-session findings browser |
| `/proofs` | Immutable proof bundles |
| `/benchmarks` | Suite browser, run matrix, policy training |
| `/policies` | Policy packs and governance rules |
| `/skills` | Skills studio, compatibility matrix, export/install |
| `/ship` | Deploy-readiness and session metrics |
| `/deploy` | Deployment advisor, cost estimates, file generation |

## CLI

```bash
controlkeel                                  # start server
controlkeel attach <agent>                   # attach agent + install native bundle
controlkeel status                           # show governed state
controlkeel findings [--severity high]       # list findings
controlkeel findings translate               # translate findings to plain English
controlkeel approve <finding-id>             # approve a finding
controlkeel proofs [--session-id ...]        # list proof bundles
controlkeel progress [--session-id ID]       # show session progress dashboard
controlkeel skills list|validate|export|install|doctor
controlkeel benchmark list|run|show
controlkeel policy list|train|promote|archive
controlkeel agents doctor                    # show attached/runnable agents
controlkeel agents monitor [--agent-id ID]  # live agent activity feed
controlkeel run task <id>                    # governed agent execution
controlkeel provider list|set-key|default|doctor
controlkeel watch                            # continuous file-watch governance
controlkeel mcp --project-root /path         # direct stdio MCP
controlkeel review plan submit --task-id 12 --body-file plan.md --json
controlkeel review plan wait --id 34 --json
controlkeel review plan open --id 34 --json
controlkeel review plan respond 34 --decision approved --json
controlkeel review socket --report report.json # ingest Socket dependency alerts
cat report.json | controlkeel review socket --stdin
```

### Deployment commands

```bash
controlkeel deploy analyze                   # detect stack, estimate costs, generate files
controlkeel deploy cost --stack phoenix      # compare hosting costs across 9 platforms
controlkeel deploy dns <stack>               # DNS and SSL setup guide
controlkeel deploy migration <stack>         # database migration guide
controlkeel deploy scaling <stack>           # scaling and infrastructure guide
```

### Cost management

```bash
controlkeel cost optimize [--session-id ID]  # get cost optimization suggestions
controlkeel cost compare [--tokens 10000]    # compare agent costs for a token budget
```

### Governance commands

```bash
controlkeel precommit-check [--enforce]      # scan staged files for policy violations
controlkeel precommit-install [--enforce]    # install git pre-commit hook
controlkeel precommit-uninstall              # remove ControlKeel pre-commit hook
controlkeel circuit-breaker status           # show circuit breaker status for agents
controlkeel circuit-breaker trip <agent-id>  # manually trip circuit breaker
controlkeel circuit-breaker reset <agent-id> # reset circuit breaker for an agent
```

### Outcome tracking

```bash
controlkeel outcome record <session-id> <outcome>  # record deploy_success, test_pass, etc.
controlkeel outcome score <agent-id>                # show agent score from outcomes
controlkeel outcome leaderboard                     # show agent leaderboard
```

## MCP tools

| Tool | Purpose |
| --- | --- |
| `ck_validate` | Run validation on code changes |
| `ck_context` | Get assembled mission context |
| `ck_finding` | Report or query findings |
| `ck_budget` | Check or update budget |
| `ck_route` | Route tasks to agents |
| `ck_delegate` | Cross-agent delegation |
| `ck_skill_list` | List available skills |
| `ck_skill_load` | Load a skill by name |
| `ck_cost_optimizer` | Get cost optimization suggestions |
| `ck_deployment_advisor` | Analyze project for deployment |
| `ck_outcome_tracker` | Record and query agent outcomes |

## Skills & plugins

Built-in skills live in `priv/skills/`. Export or install for any target:

```bash
controlkeel skills export --target claude-plugin
controlkeel skills install --target cursor-native --scope project
controlkeel plugin export codex
```

Exported bundles are written to `controlkeel/dist/<target>/`. Tagged releases also publish platform binaries, plugin tarballs, and checksums.

## Provider access

ControlKeel resolves model access in priority order: agent bridge → workspace profile → user profile → project override → local Ollama → heuristic fallback.

```bash
controlkeel provider set-key openai --value "$OPENAI_API_KEY"
controlkeel provider default openai
controlkeel provider doctor
```

No-key mode still runs governance, MCP, proofs, skills, and benchmarks — only model-backed features degrade.

## ControlKeel is not

- Another IDE or coding model
- A prompt marketplace
- Post-hoc code review only

It is occupation-first governance: users describe their work, ControlKeel maps that to domain packs, interview language, and compliance posture — plain language, not framework acronyms.

## Further reading

- [Getting started](docs/getting-started.md)
- [Control-plane architecture](docs/control-plane-architecture.md)
- [Agent integrations](docs/agent-integrations.md)
- [Support matrix](docs/support-matrix.md)
- [Autonomy and findings](docs/autonomy-and-findings.md)
- [Benchmarks](docs/benchmarks.md)
- [Demo script](docs/demo-script.md)

## Development

```bash
mix setup          # install deps, create DB, seed
mix phx.server     # run dev server
mix test           # run tests
mix precommit      # full pre-commit checks
```

Phoenix + Ecto on SQLite. Uses `Req` for HTTP. Single-binary builds via Burrito (`BURRITO_TARGET=macos_silicon MIX_ENV=prod mix release`).
