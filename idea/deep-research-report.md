# Legacy Deep Research Report: Useful Ideas to Keep

Prepared: March 27, 2026

This file is no longer a roadmap or a source of current market facts.

The original deep research report was useful because it named the product problem clearly: agent output is getting cheaper, but trust, reviewability, security, release safety, and cost control are not. ControlKeel now ships most of the architecture thesis that report argued for, so the remaining value in the document is framing, not implementation direction.

## What Was Worth Keeping

These ideas still map cleanly onto the current product:

- **The adoption-vs-trust gap**
  - agents can generate large changes quickly
  - users still need confidence that the result is reviewable, secure, scoped, and safe to ship
- **Control plane above generators**
  - ControlKeel is not the code generator
  - it governs the work around generation: routing, validation, findings, proofs, budgets, and delivery evidence
- **Governed delivery lifecycle**
  - intent intake
  - execution brief
  - task graph and routing
  - validation and findings
  - proof bundles
  - ship metrics
  - benchmarks
- **Stewardship and evidence**
  - users keep using ControlKeel because it proves governed progress over time
  - `/ship` and `/benchmarks` are the current proof-of-value surfaces

## What ControlKeel Already Ships

The following parts of the original report are already materially present in the repo:

- occupation-first onboarding and domain-pack selection
- execution brief compilation and guided mission setup
- task planning, routing, findings, budgets, and proof bundles
- FastPath, Semgrep, optional advisory, and guided auto-fix flows
- MCP runtime, typed agent integrations, proxy support, and runtime exports
- typed memory, benchmarks, and learned policy artifacts
- packaged local distribution plus partial cloud/headless operator surfaces

## What Was Intentionally Dropped

The following parts of the original report should not be revived as current truth:

- dated market, labor, and regulatory statistics
- naming and domain brainstorming
- “vibe coding” as the primary product label
- image placeholders and research citation scaffolding
- generic claims that every external tool is natively covered
- full-autopilot or “set it and forget it” language
- “PR Governor + Release Autopilot” as if it were already shipped

## What Stays Out of Scope Here

These ideas are still separate branches and are not pulled forward from this report:

- broader Team / Platform work
- full Infrastructure work
- new GitHub App, PR governor, or deploy-autopilot subsystems
- external telemetry metrics that require repository-hosting or deployment integrations

## How to Use This Legacy Note

If the old deep research report is referenced again, treat it as a source for product framing only:

- use it for the adoption-vs-trust-gap explanation
- use it for the governed delivery lifecycle story
- use it for the stewardship / evidence rationale
- do not use it as a source of truth for market claims, roadmap status, or shipped capability
