# ControlKeel Control-Plane Architecture

This document explains the current product architecture.

ControlKeel is not the code generator. It is the control plane above generators: the layer that turns agent output into governed, reviewable, production-minded delivery.

That context layer is intentionally bounded. CK exposes the repo facts an agent needs to stay oriented, plus the recent CK-visible transcript and resumable task state, without pretending to be the full coding harness or persisting hidden model reasoning.

## The control-plane map

The older strategy split the product into seven pillars. In current ControlKeel terms, those map like this:

- **Harness**: typed integrations, attach flows, runtime export, provider broker, and project bootstrap
- **Tools**: MCP runtime, skills, generated plugin bundles, and governed proxy endpoints
- **Context**: execution brief, execution posture, typed memory, proof bundles, workspace snapshots, clipped session transcript events, resume packets, and current mission state
- **Orchestration**: planner, task graph, router, Mission Control, and agent recommendations
- **Invocation**: provider resolution, budget checks, governed forwarding, and no-key fallback behavior
- **Validation**: FastPath, Semgrep, optional advisory review, findings, and guided auto-fix
- **Evidence**: Proof Browser, Ship Dashboard, and Benchmarks

## What this means in product terms

The live governed lifecycle is:

1. intent intake
2. execution brief compilation
3. execution posture compilation
4. runtime recommendation compilation
5. task graph and routing
6. validation and findings
7. proof capture
8. ship metrics
9. comparative benchmark evidence

The execution posture is the part of the brief that tells CK how to treat the runtime surface:

- use the read-only virtual workspace first for discovery and context gathering
- keep durable state in typed surfaces such as memory, proofs, traces, and outcomes rather than treating the filesystem as the source of truth
- prefer typed or code-mode execution for large API and tool surfaces when available
- keep shell as the broad fallback surface for repo mutation, test runs, and package commands
- escalate approval pressure as work moves from read-only exploration to high-impact execution

CK now also derives a runtime recommendation from that posture:

- approval-heavy or regulated briefs bias toward attach-first hosts with stronger review surfaces
- API-heavy briefs that benefit from code-mode or sandboxed typed execution can bias toward a headless runtime export such as Cloudflare Workers or Executor
- the recommendation stays grounded in the typed integration catalog so CK suggests a real attach command or runtime export path instead of a generic “use a sandbox” note
- when CK can see attached agents or already exported runtime bundles for the current workspace, it now biases the recommendation toward those live surfaces first

That is why the main surfaces stay grouped as:

- Mission Control
- Proof Browser
- Ship Dashboard
- Benchmarks

## Project rescue and unsupported tools

ControlKeel does not need a fictional universal watcher or a native integration for every generator to be useful.

When another tool already changed the repo, the current rescue path is:

1. bootstrap the governed project
2. use `controlkeel watch` for live findings and budget state
3. use `controlkeel findings`, proofs, and `ck_validate` to assess the result
4. use governed proxy only when the tool can target compatible OpenAI- or Anthropic-style endpoints

That keeps the support story honest: some tools have first-class attach flows, some work through proxy or runtime export, and unsupported tools still participate in the governance loop after bootstrap.

## New subsystems

### Deployment Advisor

Stack detection, hosting cost estimation, and deployment file generation for 6 stacks (Phoenix, React, Rails, Node, Python, static) across 9 hosting platforms. Accessible via CLI (`deploy analyze/cost/dns/migration/scaling`) and the `/deploy` web UI.

### Cost Optimizer

Model-level cost comparison and optimization suggestions. Compares 27+ LLM models across providers, identifies caching opportunities, and recommends cheaper alternatives.

### Outcome Tracker

Records agent outcomes (deploy_success, test_pass, budget_exceeded, etc.) and computes reward signals. Feeds into agent leaderboard and router weight adjustments for learned routing.

### Circuit Breaker

Per-agent anomaly detection with configurable thresholds (API call rate, file modification rate, error rate, budget burn rate). Auto-trips when thresholds are exceeded, preventing runaway agents.

### Agent Monitor

Live event tracking for all active agents. Provides real-time activity feed, agent status, and event history for debugging and observability.

### Pre-commit Hook

Git pre-commit policy enforcement. Scans staged files against active policy packs before allowing commits, with enforce mode that blocks commits on violations.

### Plain English Findings

Translates technical findings (rule IDs, categories) into plain English explanations with fix suggestions and risk descriptions.

### Progress Dashboard

Session-level progress tracking with task, finding, and budget progress, remaining blockers, and effort estimation.

## Not shipped by design

These ideas appeared in older planning documents, but they are not current product claims:

- no autonomous deployment engine
- no microVM or Firecracker / gVisor sandbox layer
- no RL / self-healing orchestration system
- no repo-native PR governor branch
- no team/platform or infrastructure completion in this doc; those remain deferred roadmap work

## Related docs

- [Getting started](getting-started.md)
- [Agent integrations](agent-integrations.md)
- [Support matrix](support-matrix.md)
- [Benchmarks](benchmarks.md)
- [Autonomy and findings](autonomy-and-findings.md)
