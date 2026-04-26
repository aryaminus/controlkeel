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
- treat network/egress as default-deny and grant capability access through explicit task-scoped reviewed allowlists
- escalate approval pressure as work moves from read-only exploration to high-impact execution

CK now also derives a runtime recommendation from that posture:

- approval-heavy or regulated briefs bias toward attach-first hosts with stronger review surfaces
- API-heavy briefs that benefit from code-mode or sandboxed typed execution can bias toward a headless runtime export such as Cloudflare Workers or Executor
- repo-discovery briefs that want a just-bash-style loop can also bias toward a CK-owned virtual-workspace runtime, where discovery stays on the read-only virtual workspace and shell remains a governed fallback
- the recommendation stays grounded in the typed integration catalog so CK suggests a real attach command or runtime export path instead of a generic “use a sandbox” note
- when CK can see attached agents or already exported runtime bundles for the current workspace, it now biases the recommendation toward those live surfaces first

## Harness and sandbox

CK is the harness and control plane, not the sandbox itself.

That distinction matters because the two layers solve different problems:

- the harness decides how work is understood, validated, resumed, reviewed, and evidenced
- the sandbox or runtime provides the isolated execution environment where code, tools, or scripts actually run

CK can attach to a host, export a headless runtime bundle, or route work toward a governed execution path without claiming that it owns every underlying sandbox substrate. The runtime can be swapped more easily than the control-plane record around it.

In CK terms, the more durable system of record is the governed trajectory-adjacent state it already owns:

- task, session, review, and proof state
- recent transcript events and transcript summaries
- resume packets and checkpoints
- typed memory, outcomes, and workspace snapshots

The sandbox filesystem still matters operationally. It may contain downloaded artifacts, generated analysis, or changed code that the next loop needs. But CK does not treat that local runtime state alone as the whole story, and it does not depend on opaque provider-managed memory as the source of truth either.

That is why CK's runtime model is intentionally split:

- the runtime or sandbox can fail, restart, or be replaced
- the governed context, findings, review state, and proof trail remain portable across those restarts
- runtime export and attach flows reuse the same task-run, validation, findings, and proof primitives instead of inventing a separate state model for each execution surface

## Enterprise control-plane posture

Another useful way to read CK is as an **enterprise control plane for agent connectivity**, not just as a single-host helper.

In current product terms, that breaks into three adjacent surfaces:

- a central provider and proxy layer
- a typed discovery/catalog layer
- a governed lineage and evidence layer

### 1. Central provider and proxy layer

CK already centralizes model and compatible API access through:

- provider brokerage and explicit fallback chains
- governed OpenAI-style and Anthropic-style proxy endpoints
- budget checks, spend alerts, and cost governance

That means teams do not all need to reinvent their own raw model wiring, budget controls, or compatible upstream proxy handling to stay inside the same governed system.

### 2. Typed discovery and catalog layer

CK also already maintains a typed integration catalog and hosted protocol discovery surfaces:

- the built-in integration catalog behind `/skills` and `GET /api/v1/skills/targets`
- hosted MCP and minimal A2A discovery
- agent-card publication for CK's hosted A2A surface
- optional ACP registry enrichment layered on top of the built-in catalog

That is not the same thing as claiming a separate enterprise “MCP registry product.” The important current truth is narrower: CK already gives organizations one typed place to describe what host/runtime surfaces exist, how they are installed, how they are reviewed, and which discovery metadata can be enriched from external registries.

### 3. Governed lineage and evidence layer

CK also ties execution back to governed state instead of leaving every agent or tool as an isolated island.

Current lineage-bearing surfaces include:

- workspace, session, task, review, and proof identifiers
- task graph edges and task-run state
- audit exports and proof bundles
- service-account scoping across workspace/session/task/review access

That is the part that makes enterprise governance practical. The point is not just “can we call a tool?” It is also “which governed workspace did this happen in, which task did it affect, what proof and review state exists, and who was allowed to see or operate it?”

## Harness principles

ControlKeel already had most of these behaviors in practice, but they are now an explicit harness contract too:

- **Context ownership over hidden mutation**
  CK treats the operator-visible brief, workspace snapshot, recent events, proof state, and typed memory as the real working context. It avoids treating silent host-side prompt edits or provider memory as the system of record.
- **Minimal stable contracts**
  CK prefers a small stable control-plane contract: bounded context, typed tools, versioned schemas, and additive integration surfaces instead of constantly reshaping the basic loop underneath the agent.
- **Lean harness over prompt bloat**
  CK prefers progressive discovery, compact repo-local instructions, and event-driven hooks over stuffing every turn with large static system guidance, always-loaded skills, or repetitive tone/style reminders. The goal is to keep the harness useful without making the runtime fight unnecessary injected context.
- **Smart-zone task sizing**
  CK treats context growth as a quality and budget risk. Human-in-loop planning should split large work into approved, dependency-aware backlog/DAG items before AFK agents execute them, rather than letting one session drift into a long, compacted “dumb zone.”
- **Vertical slices over horizontal phases**
  Plans should prefer tracer-bullet slices that cross storage, domain logic, and user-visible feedback so tests and review can exercise an integrated path early. Pure schema/API/UI phases are a warning sign unless they are explicitly justified.
- **Bounded AFK, not unattended autonomy**
  CK models AFK execution as a night shift that catches up to day-shift planning. Humans still own requirements, PRD destination, QA, and merge decisions; planner agents should launch only unblocked sandboxed slices, and each implementation branch needs automated review plus human QA follow-up before it is trusted.
- **Design interfaces before delegating internals**
  For new or risky modules, CK should ask for at least two materially different interface shapes before implementation. The winning design should keep callers simple, hide complexity behind a deep module boundary, and make misuse hard.
- **Domain language and durable issues**
  Planning and QA artifacts should use project domain terms and documented decisions, not transient file paths or line numbers. Issues should describe behavior, expected outcomes, reproduction steps, blockers, and acceptance criteria so they survive refactors.
- **Progressive skill disclosure**
  Skills should keep descriptions precise and SKILL.md short. Detailed references and deterministic scripts belong in separate resources so agents pull them only when needed.
- **Pull detailed standards, push review criteria**
  Keep always-on system guidance small. Let implementers pull detailed standards from skills or memory when needed, then push the relevant standards into fresh-context review so code style, security, and architecture constraints are checked deliberately.
- **Observable compaction and recovery**
  Compaction, partial reads, findings, reviews, and delegated execution are meant to stay inspectable through runtime context integrity, recent events, resume packets, and proof bundles.
- **Truthful extensibility**
  CK meets each host on the native surface it actually exposes: skills, hooks, plugins, commands, runtime bundles, or protocol tools. It does not pretend every host has the same extension depth.
- **Portable provider choice**
  CK keeps provider selection, fallback chains, and budget pressure explicit so teams can move between hosts and providers without turning opaque host memory into a hidden dependency.

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
