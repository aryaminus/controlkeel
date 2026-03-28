# Legacy HELM Plan: Useful Ideas to Keep

Prepared: March 27, 2026

This file is no longer a build plan.

The old HELM document was created before the current ControlKeel product shape existed. Most of its core mechanics are already shipped in ControlKeel, and the remaining large branches are now tracked separately in the current remaining-work docs.

## What Was Worth Keeping

These ideas still map cleanly onto the current product:

- **Occupation-first onboarding**
  - users describe what kind of work they do instead of selecting a compliance framework
  - domain packs stay a product differentiator, not just internal configuration
- **Plain-language governance**
  - findings, approvals, and budget/risk messages should stay understandable to non-experts
  - the product should keep selling governed autonomy, not full autopilot
- **Integration by mechanism**
  - native attach
  - governed proxy
  - runtime export
  - provider-only backend profiles
  - post-hoc fallback governance for unsupported tools
- **Operating modes**
  - local packaged mode is a real product lane
  - cloud/headless mode exists only partially today
  - team and enterprise platform work remains a later branch

## What ControlKeel Already Ships

The following parts of the old HELM vision are already materially present in the repo:

- control-tower / control-plane product positioning
- guided onboarding and domain-pack selection
- task planning, routing, budget controls, and findings
- FastPath + Semgrep + optional advisory validation
- proof bundles, audit exports, and ship metrics
- typed memory and benchmark workflows
- MCP runtime, native skills, plugin bundles, proxy paths, and runtime exports
- packaged local distribution

## What Stays Out of Scope Here

These are not pulled from the old HELM plan because they belong to the current remaining-work branches:

- broader Team / Platform work
- full Infrastructure work
- full multi-node cloud runtime
- full enterprise self-host / org administration story

## What Was Intentionally Dropped

The following parts of the old HELM plan should not be revived:

- the `HELM` product name and domain discussion
- old market and regulatory statistics
- Bakeware references
- the 6-week MVP build plan
- claims about “for everyone” or “826 occupations”
- full-autopilot / “set it and forget it” language
- old porting instructions from other codebases

## How to Use This Legacy Note

If the old HELM plan is referenced again, treat it as a historical source for framing only:

- use it for occupation-first messaging
- use it for clearer integration-mode explanation
- use it for clearer local/cloud/team mode explanation
- do not use it as a source of truth for roadmap, architecture, or product completeness
