# ControlKeel

[![CI](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml)
[![Release Smoke](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml)
[![Latest Release](https://img.shields.io/github/v/release/aryaminus/controlkeel.svg)](https://github.com/aryaminus/controlkeel/releases/latest)
[![npm bootstrap](https://img.shields.io/npm/v/%40aryaminus/controlkeel.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel)

> Agent output is cheap. Reviewability, security, release safety, and cost control are not.

**ControlKeel is the cerebellum for agent-generated software delivery.** ControlKeel sits between your coding agents and production, comparing *intended* delivery against *actual* delivery, catching governance drift before it ships and turning intent into governed tasks through validation and review gates.

It does not replace the coding model underneath. It governs the delivery layer around that model: routing, review, findings, proofs, policy, budgets, deployment readiness, and the governed context agents need to keep work grounded in the repo and session state.

## Quick start

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
controlkeel attach opencode

# 4. Inspect governance state
controlkeel status
controlkeel findings

# 5. Use guided CLI help whenever you need it
controlkeel help
controlkeel help codex
controlkeel help "how do i attach opencode"
```

For a full first-run walkthrough, see [docs/getting-started.md](docs/getting-started.md).

## Published surfaces

ControlKeel has one primary CLI and a smaller set of published companion packages. Everything else ships as release bundles or attach-time generated assets.

| Surface | Version | Install / use |
| --- | --- | --- |
| ControlKeel CLI bootstrap | [![npm bootstrap](https://img.shields.io/npm/v/%40aryaminus/controlkeel.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel) | `npm i -g @aryaminus/controlkeel` |
| OpenCode companion package | [![npm opencode](https://img.shields.io/npm/v/%40aryaminus/controlkeel-opencode.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel-opencode) | Add `"plugin": ["@aryaminus/controlkeel-opencode"]` to `opencode.json` |
| Pi companion package | [![npm pi](https://img.shields.io/npm/v/%40aryaminus/controlkeel-pi-extension.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel-pi-extension) | `pi install npm:@aryaminus/controlkeel-pi-extension` |
| Release bundles and VSIX | [![GitHub release](https://img.shields.io/github/v/release/aryaminus/controlkeel.svg?label=release%20bundles)](https://github.com/aryaminus/controlkeel/releases/latest) | Tagged releases include platform binaries, plugin tarballs, exported native bundles, and `controlkeel-vscode-companion.vsix` |

Release-only bundles currently cover the unpublished host artifacts such as Claude, Copilot, Codex, Augment, Gemini CLI, Amp, OpenClaw, and other exported native companions. Those surfaces follow the repository release version rather than separate package registries.

## Supported hosts

ControlKeel supports hosts through a few real mechanisms:

- Native attach: `controlkeel attach <host>` installs MCP config plus the strongest repo-native companion CK can truthfully ship.
- Direct host install: some hosts also support a package, plugin, VSIX, or extension-link path.
- Hosted protocol access: remote clients can use hosted MCP and minimal A2A.
- Runtime export: headless systems such as Devin and Open SWE get runtime bundles instead of fake attach commands.
- Provider-only and fallback governance: unsupported generators can still be governed through bootstrap, findings, proofs, and validation flows.

Common attach targets today:

- Hook-native: `claude-code`, `copilot`, `windsurf`, `cline`, `kiro`, `augment`
- Plugin-native: `opencode`, `amp`
- File-plan-mode: `pi`
- Prompt or command-native: `continue`, `gemini-cli`, `goose`, `roo-code`
- Browser or embed companion: `vscode`
- Review-only or command-driven: `codex-cli`, `aider`

Use the docs below for the precise truth per host:

- [docs/direct-host-installs.md](docs/direct-host-installs.md)
- [docs/support-matrix.md](docs/support-matrix.md)
- [docs/agent-integrations.md](docs/agent-integrations.md)

## What ControlKeel exposes

Web app:

- `/start` for onboarding and execution brief creation
- `/missions/:id` for mission control and approvals
- `/findings` for cross-session findings
- `/proofs` for immutable proof bundles
- `/skills` for install/export compatibility and bundle inventory
- `/ship` for deploy readiness and session metrics

CLI:

```bash
controlkeel attach <agent>
controlkeel status
controlkeel findings
controlkeel proofs
controlkeel skills list
controlkeel plugin install codex
controlkeel run task <id>
controlkeel help
```

Full command coverage is available in the CLI itself through `controlkeel help`.

For MCP tool details, hosted protocol access, and the exact `ck_context` contract, use [docs/agent-integrations.md](docs/agent-integrations.md) and [docs/support-matrix.md](docs/support-matrix.md).

## Docs

Start here:

- [docs/README.md](docs/README.md)
- [docs/getting-started.md](docs/getting-started.md)
- [docs/direct-host-installs.md](docs/direct-host-installs.md)

Reference:

- [docs/qa-validation-guide.md](docs/qa-validation-guide.md)
- [docs/support-matrix.md](docs/support-matrix.md)
- [docs/agent-integrations.md](docs/agent-integrations.md)
- [docs/autonomy-and-findings.md](docs/autonomy-and-findings.md)
- [docs/benchmarks.md](docs/benchmarks.md)

Architecture and release operations:

- [docs/control-plane-architecture.md](docs/control-plane-architecture.md)
- [docs/host-surface-parity.md](docs/host-surface-parity.md)
- [docs/integration-validation-checklist.md](docs/integration-validation-checklist.md)
- [docs/release-verification.md](docs/release-verification.md)

## Development

```bash
mix setup
mix phx.server
mix test
mix precommit
```

Phoenix + Ecto on SQLite. Uses `Req` for HTTP. Single-binary builds ship through Burrito and GitHub Releases.
