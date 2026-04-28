# ControlKeel

[![CI](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml)
[![Release Smoke](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml)
[![Latest Release](https://img.shields.io/github/v/release/aryaminus/controlkeel.svg)](https://github.com/aryaminus/controlkeel/releases/latest)
[![npm bootstrap](https://img.shields.io/npm/v/%40aryaminus/controlkeel.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel)

> Agent output is cheap. Governed delivery is not.

**ControlKeel is the control plane for agent-generated software delivery.** It sits between your coding agents and production as company brain: comparing *intended* delivery against *actual* delivery, catching governance drift before it ships and turning intent into governed tasks through findings and proofs, enforcing validation and review gates, and keeping work resumable across any host.

---

## Why this exists

You already have an AI coding agent. Maybe you have a `CLAUDE.md` or a rules file telling it what not to do. So why would you need something else?

Because a rules file is a promise made *to* the model. ControlKeel enforces the *output*. ControlKeel's deterministic scanner checks what the model *produced*, not just what it was *told*, and blocks or flags violations before they ship.

Beyond the scanner, CK also provides what no single agent host gives you portably: task continuity and resume context, review gates and approval flows, proof bundle states into typed memory, budget and cost control, reusable operational context, and cross-host consistency — whether you are using Claude Code, Codex, OpenCode, Copilot, or anything else.

---

## Quick start

### One-line setup via your agent

Copy/paste this into your agent (OpenCode, Claude, Codex, etc.):

```text
Set up ControlKeel end-to-end for this repository with minimal user action: read and follow https://raw.githubusercontent.com/aryaminus/controlkeel/main/README.md, https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/getting-started.md, https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/direct-host-installs.md, https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/support-matrix.md, and https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/agent-integrations.md; detect this host's capabilities, install ControlKeel if missing, run controlkeel setup in the repo, then attach the strongest active supported host path first (attach additional configured hosts only when they add real value for this workspace) with plugin and MCP plus skills/hooks/agents as available; run controlkeel attach doctor, controlkeel provider doctor, controlkeel status, controlkeel findings, and the host-specific MCP check, and if a fix is safe and local apply it then re-verify; if the host requires a trusted project/workspace, restart after attach/plugin changes, needs manual provider configuration, or a plan review cannot auto-wait to approved, pause and ask the user to take that step before continuing; redact proxy tokens/secrets from any shared logs; for Codex ensure the project is trusted and restart Codex after attach/plugin changes.
```

### Install ControlKeel

```bash
# Homebrew (macOS and Linux x86_64)
brew tap aryaminus/controlkeel && brew install controlkeel

# npm bootstrap (macOS x86_64/arm64, Linux x86_64, Windows x86_64)
npm i -g @aryaminus/controlkeel
# or: pnpm add -g @aryaminus/controlkeel
# or: yarn global add @aryaminus/controlkeel

# one-off run
npx @aryaminus/controlkeel@latest

# release installers
curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh
```

```powershell
irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex
```

### First governed run

```bash
# 1. Start ControlKeel
controlkeel

# 2. In the target repo, bootstrap and inspect the environment
controlkeel setup

# 3. Attach a supported host
controlkeel attach claude-code   # or opencode, codex-cli, copilot, etc.

# 4. Inspect governance state
controlkeel status
controlkeel findings

# 5. Use guided CLI help whenever you need it
controlkeel help
controlkeel help codex
controlkeel help "how do i attach opencode"
```

For a full first-run walkthrough, see [docs/getting-started.md](docs/getting-started.md).

---

## Why use ControlKeel? Benchmark-backed comparison

ControlKeel adds a governance layer around agent output: fast deterministic checks, optional in-agent CK validation, review gates, proof, and budget visibility. The table below is intentionally user-facing: it shows what a team gets from each level of CK integration without requiring you to run the benchmark yourself. Full reproducibility details and caveats live in [docs/benchmark-evidence.md](docs/benchmark-evidence.md).

### OpenCode / GPT-5.5 comparison (`host_comparison_v1`, 12 risky scenarios)

| Option | What it means | Catch | Block | Median time | Tokens | Best use |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Raw OpenCode | Ask the model and trust the answer | 1/12 | 0/12 | 17,050 ms | 290,327 | Baseline only; not enough for risky changes |
| CK-attached | CK is installed/available, model may call it | 4/12 | 3/12 | **10,818 ms** | 254,581 | Lightweight default when you want CK available without forcing tool use |
| Exhaustive CK-active | Ask the model to inspect every CK surface | 2/12 | 0/12 | 47,560 ms | 510,280 | Demonstrates surface availability, but too slow/expensive for routine use |
| **CK-bounded active** | Model calls CK context + validation, then stops | **5/12** | **3/12** | 23,772 ms | **255,941** | Best practical active-governance tradeoff so far |
| **CK deterministic scanner** | CK validates directly, no model required | **12/12** | **9/12** | **~50 ms** | **0 provider tokens** | Fastest enforcement baseline; ideal for preflight and CI-style checks |

What users should take away:

- **Security lift:** CK raises systematic detection from raw model output's 1/12 to 5/12 with bounded active governance, and 12/12 with direct deterministic validation.
- **Efficiency:** bounded active used about half the tokens of exhaustive active while catching more issues.
- **Cost control:** OpenCode reported `$0` cost in JSON events, so we treat tokens/time as the reliable cost proxy. Direct CK scanning uses no provider tokens.
- **Practical workflow:** use deterministic CK validation as the fast gate, and use bounded active governance when you want the agent itself to consult CK before responding.

### Other agents (pending)

| Host | Mode | Suite | Catch | Block |
| --- | --- | --- | ---: | ---: |
| Codex | Raw / no CK | `host_comparison_v1` | TBD | TBD |
| Codex | CK-attached | `host_comparison_v1` | TBD | TBD |
| Claude Code | Raw / no CK | `host_comparison_v1` | TBD | TBD |
| Claude Code | CK-attached | `host_comparison_v1` | TBD | TBD |

To run a host comparison: `controlkeel benchmark run --suite host_comparison_v1 --subjects controlkeel_validate,<host>_manual`. See [docs/benchmark-guide.md](docs/benchmark-guide.md).

---

## Published surfaces

ControlKeel has one primary CLI and a smaller set of published companion packages. Everything else ships as release bundles or attach-time generated assets.

| Surface | Version | Install / use |
| --- | --- | --- |
| ControlKeel CLI bootstrap | [![npm bootstrap](https://img.shields.io/npm/v/%40aryaminus/controlkeel.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel) | `npm i -g @aryaminus/controlkeel` |
| Skills.sh / AgentSkills install | [Skills docs](https://skills.sh/docs) | `npx skills add https://github.com/aryaminus/controlkeel --skill controlkeel-governance` |
| OpenCode companion package | [![npm opencode](https://img.shields.io/npm/v/%40aryaminus/controlkeel-opencode.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel-opencode) | Add `"plugin": ["@aryaminus/controlkeel-opencode"]` to `opencode.json`; MCP uses `mcp.controlkeel` local command-array config; attach installs `.opencode/*` plus `.agents/skills` compatibility skills |
| Pi companion package | [![npm pi](https://img.shields.io/npm/v/%40aryaminus/controlkeel-pi-extension.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel-pi-extension) | `pi install npm:@aryaminus/controlkeel-pi-extension` |
| Release bundles and VSIX | [![GitHub release](https://img.shields.io/github/v/release/aryaminus/controlkeel.svg?label=release%20bundles)](https://github.com/aryaminus/controlkeel/releases/latest) | Tagged releases include platform binaries, plugin tarballs, exported native bundles, and `controlkeel-vscode-companion.vsix` |

Release-only bundles currently cover the unpublished host artifacts such as Claude, Copilot, Codex, Augment, Gemini CLI, Amp, OpenClaw, and other exported native companions. Those surfaces follow the repository release version rather than separate package registries.

---

## How Claude Code is configured with ControlKeel

Claude's governed path is:

1. Claude calls `ck_context` → gets bounded session state instead of relying on raw chat history
2. Claude calls `ck_validate` on proposed code or shell → CK's scanner checks output deterministically
3. CK records findings → blocked patterns never reach the repo
4. Proof bundles capture what happened → auditable, resumable, portable

Without this loop, Claude is still writing code — but nothing is checking what it actually produced.

---

## What ControlKeel provides beyond validation

Validation is the most visible part. CK also provides:

**Governed context for agents (`ck_context`)** — bounded, session-aware, workspace-aware state: current task, proof summary, memory hits, resume packet, workspace snapshot, budget summary, recent transcript events. Agents start from grounded context instead of raw chat history or repeated shell exploration.

**Task continuity and resume** — sessions, tasks, task graph, checkpoints, and resume packets. Work survives runtime restarts and host switches.

**Findings and review gates** — every blocked or warned pattern becomes a governed finding with state (open, blocked, escalated, approved, denied), human gate hints, and Mission Control visibility. Review is part of the delivery system, not detached commentary.

**Proof bundles** — immutable evidence of what happened, what was reviewed, what was validated, what findings existed. Hosts show chat history. CK stores proof bundles.

**Budget and cost control** — session budgets, 24-hour rolling limits, proxy token estimates, circuit breakers on API-call rate, file-modification rate, and budget-burn rate. See [docs/cost-governance.md](docs/cost-governance.md).

**Cross-host consistency** — the same governance loop works across Claude Code, Codex, OpenCode, Copilot, Cline, Windsurf, Continue, Goose, Roo Code, and others. See [docs/support-matrix.md](docs/support-matrix.md).

**Ship readiness** — deploy-ready proof state, outcome metrics, and comparative benchmark evidence. The question is not just "did the agent finish?" but "is this ready to ship?"

---

## Supported hosts

ControlKeel supports hosts through a few real mechanisms:

- **Native attach**: `controlkeel attach <host>` installs MCP config plus the strongest repo-native companion CK can truthfully ship.
- **Direct host install**: some hosts also support a package, plugin, VSIX, or extension-link path.
- **Hosted protocol access**: remote clients can use hosted MCP and minimal A2A.
- **Runtime export**: headless systems such as Devin and Open SWE get runtime bundles instead of fake attach commands.
- **Provider-only and fallback governance**: unsupported generators can still be governed through bootstrap, findings, proofs, and validation flows.

Common attach targets today:

- Hook-native: `claude-code`, `copilot`, `windsurf`, `cline`, `kiro`, `augment`
- Plugin-native: `opencode`, `amp`
- File-plan-mode: `pi`
- Prompt or command-native: `continue`, `gemini-cli`, `goose`, `roo-code`
- Hook, skill, and MCP-native with headless/remote support: `letta-code`
- Browser or embed companion: `vscode`
- Review-only, command-driven, or local-plugin-capable: `codex-cli`, `aider`

Use the docs below for the precise truth per host:

- [docs/direct-host-installs.md](docs/direct-host-installs.md)
- [docs/support-matrix.md](docs/support-matrix.md)
- [docs/agent-integrations.md](docs/agent-integrations.md)

---

## What ControlKeel exposes

Web app:

- `/start` for onboarding and execution brief creation
- `/missions/:id` for mission control and approvals
- `/findings` for cross-session findings
- `/proofs` for immutable proof bundles
- `/skills` for install/export compatibility and bundle inventory
- `/ship` for deploy readiness and session metrics
- `/benchmarks` for benchmark runs and cross-agent comparison

CLI:

```bash
controlkeel attach <agent>
controlkeel status
controlkeel findings
controlkeel proofs
controlkeel update
controlkeel skills list
controlkeel plugin install codex
controlkeel run task <id>
controlkeel benchmark run --suite vibe_failures_v1 --subjects controlkeel_validate
controlkeel help
```

For Codex there are two different CK install paths:

- `controlkeel attach codex-cli` installs the native `.codex/` companion files, skills, commands, agents, and local MCP wiring.
- `controlkeel plugin install codex` installs a local plugin bundle plus a local marketplace manifest for repo-local or home-local discovery.

That local marketplace path is not the same thing as being listed in OpenAI's curated Codex plugin catalog.

Full command coverage is available in the CLI itself through `controlkeel help`.

For MCP tool details, hosted protocol access, and the exact `ck_context` contract, use [docs/agent-integrations.md](docs/agent-integrations.md) and [docs/support-matrix.md](docs/support-matrix.md).

---

## Docs

Start here:

- [docs/README.md](docs/README.md)
- [docs/getting-started.md](docs/getting-started.md)
- [docs/direct-host-installs.md](docs/direct-host-installs.md)
- [docs/explaining-controlkeel.md](docs/explaining-controlkeel.md)

Reference:

- [docs/qa-validation-guide.md](docs/qa-validation-guide.md)
- [docs/support-matrix.md](docs/support-matrix.md)
- [docs/agent-integrations.md](docs/agent-integrations.md)
- [docs/autonomy-and-findings.md](docs/autonomy-and-findings.md)
- [docs/benchmarks.md](docs/benchmarks.md)
- [docs/benchmark-guide.md](docs/benchmark-guide.md)
- [docs/benchmark-evidence.md](docs/benchmark-evidence.md)
- [docs/cost-governance.md](docs/cost-governance.md)

Architecture and release operations:

- [docs/control-plane-architecture.md](docs/control-plane-architecture.md)
- [docs/host-surface-parity.md](docs/host-surface-parity.md)
- [docs/how-controlkeel-works.md](docs/how-controlkeel-works.md)
- [docs/integration-validation-checklist.md](docs/integration-validation-checklist.md)
- [docs/release-verification.md](docs/release-verification.md)

---

## Development

```bash
mix setup
mix phx.server
mix test
mix precommit
```

Phoenix + Ecto on SQLite. Uses `Req` for HTTP. Single-binary builds ship through Burrito and GitHub Releases.

To run the benchmark suite locally:

```bash
controlkeel benchmark run --suite vibe_failures_v1 --subjects controlkeel_validate
controlkeel benchmark run --suite benign_baseline_v1 --subjects controlkeel_validate
controlkeel benchmark export <RUN_ID> --format json
```

See [docs/benchmark-guide.md](docs/benchmark-guide.md) for multi-host comparison setup and how to add Codex or OpenCode as subjects.
