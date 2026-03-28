# ControlKeel Product Strategy

Prepared: March 27, 2026

## Summary

ControlKeel is the control tower that turns agent-generated work into secure, scoped, validated, production-ready delivery.

The product is no longer an early architecture concept. The core control loop is already real in the repo:

- intent compilation
- task graph planning
- routing and provider brokerage
- policy and governed validation
- immutable proof bundles
- typed memory
- benchmarks
- typed agent/runtime/provider integrations

This document is no longer a build checklist. It is the current product strategy and evidence plan for what the product is, who it is for, and what metrics prove that it matters.

## Product Positioning

ControlKeel sits above coding agents such as Claude Code, Codex, Cline, OpenCode, Cursor, Windsurf, Copilot / VS Code, and similar systems.

It is not:

- another IDE
- another coding model
- a prompt marketplace
- post-hoc code review only
- deployment-only tooling

Its job is to provide the missing control layer around agent work:

- clarify intent before execution
- break work into manageable governed steps
- route work through the right agent/runtime/provider path
- stop unsafe or out-of-policy actions
- preserve continuity across long-running work
- attach immutable evidence to delivery decisions

## Default Customer and Wedge

The default customer remains:

- serious solo builders
- founders and operators who ship with coding agents
- very small teams running agent-heavy workflows

This is still the right wedge because these users feel the pain of broken prompts, oversized changes, approval ambiguity, and missing proof immediately. They also adopt faster than enterprise buyers.

Team / platform expansion remains real, but it is a later branch and should not replace the current product story.

## Current Product Story

The product should be explained as one proof-first control loop:

- **Mission Control** shows live task state, findings, approvals, risk, and blocked work.
- **Proof Browser** shows immutable audit artifacts, deploy readiness, rollback guidance, and compliance attestations.
- **Ship Dashboard** shows governed funnel and outcome metrics.
- **Benchmarks** show comparative evidence for governed runs and policy performance.

This “proof console” framing is stronger than describing the product as a collection of separate tools. The user value is the closed loop from vague intent to evidence-backed delivery.

## Why Users Pay

ControlKeel earns its place when it shows measurable value, not when it merely wraps agents with more UI.

The strongest metrics that can be computed from current product data are:

- proof-backed task coverage
- deploy-ready task rate
- cost per deploy-ready task
- resume success rate after checkpoints
- risky finding intervention rate
- task completion rate by agent
- time to first governed finding
- time to first deploy-ready proof

These metrics map directly to the product promise:

- safer delivery
- tighter task scope
- lower waste
- better continuity across long-running work
- more trustworthy governed autonomy

## Deferred Evidence

Some strategic metrics are still valid, but they require external integrations that are not yet part of the current product data model:

- PR size reduction
- failed deploy rate reduction
- review readability
- prompt refinement reduction
- security incident reduction

These should remain future evidence goals, not present-tense product claims, until Git/provider/deploy telemetry exists to measure them honestly.

## Near-Term Product Direction

The near-term product direction is not to rebuild shipped architecture. It is to sharpen the story and evidence around what already exists:

1. Keep the product narrative consistent across homepage, README, onboarding, and getting-started.
2. Keep the serious-solo-builder / tiny-team wedge explicit.
3. Keep “proof console” as the umbrella framing for Mission Control, Proof Browser, Ship Dashboard, and Benchmarks.
4. Keep live metrics limited to what the current persisted data can support honestly.

## Roadmap Buckets

The repo now has three explicit roadmap buckets:

1. **Canonical remaining work**
   - `Team / Platform`
   - `Infrastructure`
2. **Recent control-plane hardening**
   - `Repo Governance and Delivery Controls`
   - `Protocol Interop Hardening`
   - `Bidirectional Agent Interop, Plugins, and Executor Layer`
3. **Explicit non-goals for now**
   - microVM sandboxing
   - autonomous hosting / scale-to-zero
   - RL / self-healing systems
   - compliance-guarantee claims
   - universal native support for every external tool

The remaining-work bucket lives in `controlkeel-final-build-plan.md`. Everything else in `idea/archive/` is historical source material, not live roadmap.

## Recent Control-Plane Hardening

The most recent completed slices deepened ControlKeel's role above generator output without reopening deferred platform or infrastructure work.

**Repo Governance and Delivery Controls** added:

- diff and patch review through `controlkeel review diff` and `controlkeel review pr`
- proof-backed release readiness through `controlkeel release-ready`
- cheap GitHub workflow scaffolding through `controlkeel govern install github`
- matching REST surfaces for review, readiness, and scaffold installation

**Protocol Interop Hardening** added:

- hosted MCP auth aligned with current authorization guidance
- service-account client-credentials flow for hosted MCP and A2A
- optional ACP registry awareness without making the registry the source of truth
- a minimal A2A surface for context, validation, findings, budgets, and routing

**Bidirectional Agent Interop, Plugins, and Executor Layer** added:

- a true two-way integration matrix for how agents use CK and how CK runs them
- first-class Codex, Claude, Copilot, and OpenClaw plugin bundle paths
- target-aware skill rendering and native bundle promotion for Cursor, Windsurf, and Continue
- governed agent execution through embedded, handoff, and runtime modes
- delegation capability so agents can ask ControlKeel to run other agents without bypassing policy gates

These three slices now represent the current boundary of the non-platform control plane.

## Out of Scope Here

This strategy document does not reopen separate remaining-work branches that are already tracked elsewhere:

- Team / Org Platform
- Infrastructure

It also does not reopen the deliberate non-goals listed above.

Those remain in the dedicated remaining-work docs.
