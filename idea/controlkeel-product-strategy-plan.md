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

## Out of Scope Here

This strategy document does not reopen separate remaining-work branches that are already tracked elsewhere:

- Team / Org Platform
- Infrastructure

Those remain in the dedicated remaining-work docs.
