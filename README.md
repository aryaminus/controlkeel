# ControlKeel

[![CI](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml)
[![Release Smoke](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml)
[![Latest Release](https://img.shields.io/github/v/release/aryaminus/controlkeel.svg)](https://github.com/aryaminus/controlkeel/releases/latest)
[![npm bootstrap](https://img.shields.io/npm/v/%40aryaminus/controlkeel.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel)
[![Socket Badge](https://badge.socket.dev/npm/package/@aryaminus/controlkeel)](https://socket.dev/npm/package/@aryaminus/controlkeel/overview)
[![controlkeel MCP server](https://glama.ai/mcp/servers/aryaminus/controlkeel/badges/score.svg)](https://glama.ai/mcp/servers/aryaminus/controlkeel)

> Turn the way your team works into enforceable memory for AI agents. - [@arya_minus](https://x.com/arya_minus/status/2066580759209816418)

**ControlKeel is an agent control plane for day-to-day governed engineering.** Through observation, findings and evaluation, it learns your intent rules, review taste and delivery habits, turning them into typed memory, policy checks and proof bundles. CK sits between your coding agents and production as a portable "company brain": comparing *intended* delivery against *actual* delivery and turning raw agent intent into policy-validated tasks.

If you're using an AI agent today, you probably have an `*.md` telling it how to behave. But a rules/specs file is just a promise made *to* the model. **ControlKeel enforces the output.** Beyond just catching bugs, CK solves the "Unknown Unknowns" problem: having to re-explain your domain knowledge in every single session.

## Product loop

1. **Capture intent and policy** — scope, risk, budget, domain pack, and human taste become CK state.
2. **Validate agent output** — deterministic checks and optional advisory review produce findings before risky work reaches main.
3. **Gate only when needed** — humans approve high-impact actions when intent, risk, or policy requires it.
4. **Persist evidence** — findings, reviews, proofs, memory, cost, and task outcomes survive host switches.
5. **Improve with evals** — traces and recurring failures become bounded regression evidence for specific suites and subjects.

ControlKeel transforms your domain knowledge from "raw" intent and "shelfware" documentation into a living system that remembers, enforces, and evolves.

## Quick start

### One-line setup via your agent

Copy/paste this into your agent (OpenCode, Codex, Claude, or another supported host):

```text
Set up ControlKeel for this repository. Read and follow https://raw.githubusercontent.com/aryaminus/controlkeel/main/README.md, https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/getting-started.md, https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/support-matrix.md, and https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/agent-integrations.md. Install ControlKeel if missing, run `controlkeel setup`, detect this agent host, attach the strongest supported path with `controlkeel attach <host>`, then run `controlkeel attach doctor`, `controlkeel provider doctor`, `controlkeel status`, `controlkeel findings`, and the host-native MCP check. If CK is available only as MCP, call `ck_attach` for this host. Apply only safe local fixes and redact secrets from logs. Pause and ask before continuing if the host needs workspace trust, manual provider configuration, a restart after attach/plugin changes, or a plan-review approval that cannot auto-wait. Ensure the project is trusted and restart the host after attach/plugin changes.
```

### CLI install

Install the CLI:

```bash
brew tap aryaminus/controlkeel && brew install controlkeel
# or
npm i -g @aryaminus/controlkeel
# or
curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh
```

Windows PowerShell:

```powershell
irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex
```

First governed run:

```bash
controlkeel
controlkeel setup
controlkeel attach opencode   # project scope by default; use another supported host as needed
controlkeel attach doctor
controlkeel provider doctor
controlkeel status
controlkeel findings
```

Run setup and attach from the repository you want to govern. Project scope writes host files only inside that repository. `--scope user` writes host-level files under your user configuration only for targets that explicitly support user scope; it does not turn project binding or proof state into global state.

For the complete first-run path, use [docs/getting-started.md](docs/getting-started.md). For host truth, use [docs/support-matrix.md](docs/support-matrix.md) and [docs/agent-integrations.md](docs/agent-integrations.md).

## Benchmark-backed evidence

ControlKeel includes a persisted benchmark engine. Current user-facing evidence is bounded to the named suite, subject, and scoring definition below; [docs/benchmarks.md](docs/benchmarks.md) is the canonical reference for full tables, caveats, JSON exports, and agent-host protocols.

### Verified with-vs-without-CK baseline (`host_comparison_v1`, 12 risky scenarios)

Verified with ControlKeel `0.3.45`:

- Risky suite `host_comparison_v1`: `null_policy_baseline` caught **0/12**; `controlkeel_validate` caught **12/12**, blocked **9/12**, and hit expected rules **9/12** with median deterministic validation time **52 ms**, **0 provider tokens**.
- Paired benign suite `benign_baseline_v1`: `controlkeel_validate` produced **0/10 catches**, **0/10 blocks**, FPR **0.000**, median deterministic validation time **42 ms**, **0 provider tokens**.

Read the numbers precisely: deterministic scanner evidence is not the same as model-backed agent-host evidence. Reproduction commands and the OpenCode/Copilot/Claude/Codex comparison protocol live in [docs/benchmarks.md](docs/benchmarks.md).

## What ships today

- **Local governance:** CLI, the full local stdio MCP tool set, project binding, host attach/export bundles, scanner validation, findings, reviews, proof bundles, budgets, and typed memory.
- **Host and runtime support:** native attach for supported hosts, runtime exports for headless/outer-loop systems, a narrower OAuth-scoped hosted MCP set, minimal A2A, and fallback validation/proxy paths.
- **Team/project operations:** org membership, invitations, OIDC/SAML auth surfaces, workspace GitHub repo bindings, service accounts, webhooks, workspace tool policy, and policy-set APIs.
- **Cloud evidence paths:** opt-in cloud telemetry, workspace keys, cloud run packages, runtime callbacks, and dormant-until-configured bidirectional sync for findings, reviews, digests, and memory records.
- **Observability loop:** timelines, memory quality, costs, trends, problem clusters, eval candidates, benchmark drafts/history, and promotion advisories.

## Docs map

- [docs/README.md](docs/README.md) — documentation map by job
- [docs/getting-started.md](docs/getting-started.md) — install to first finding
- [docs/support-matrix.md](docs/support-matrix.md) — canonical host/protocol inventory
- [docs/agent-integrations.md](docs/agent-integrations.md) — integration mechanisms and support tiers
- [docs/benchmarks.md](docs/benchmarks.md) — benchmark scoring, metadata, and claim discipline
- [docs/observability-feedback-loop.md](docs/observability-feedback-loop.md) — local evidence-to-regression loop
- [docs/control-plane-claim-matrix.md](docs/control-plane-claim-matrix.md) — README claim-to-test matrix for governance, memory, cloud sync, and human gates
- [docs/api-reference.md](docs/api-reference.md) and [docs/cli-reference.md](docs/cli-reference.md) — code-aligned surfaces
- [docs/packages.md](docs/packages.md) — package and distribution catalog
- [docs/self-hosting.md](docs/self-hosting.md) — self-host deployment guidance

## Development

```bash
mix setup
mix phx.server
mix test
mix precommit
```

Phoenix + Ecto on SQLite. Uses `Req` for HTTP. Single-binary builds ship through Burrito and GitHub Releases.
