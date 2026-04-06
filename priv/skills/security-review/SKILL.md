---
name: security-review
description: "Run a structured security review before marking a task done. Use this for code, config, architecture, or release reviews that need OWASP, baseline pack, and domain-pack coverage."
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
metadata:
  author: controlkeel
  version: "2.0"
  category: security
  ck_mcp_tools:
    - ck_validate
    - ck_context
    - ck_finding
    - ck_regression_result
---

# Security Review Skill

Use this skill before closing a task, approving a proof bundle, or reviewing a risky diff.

## Review flow

1. Call `ck_context` to load the domain pack, risk tier, open findings, instruction hierarchy, and design-drift signals.
2. Run `ck_validate` on the relevant code or config slices, including trust-boundary metadata when the proposed action was influenced by web, tool, skill, or mixed-provenance content.
3. Walk the review checklist in [references/review-checklist.md](references/review-checklist.md).
4. Persist any missed issue with `ck_finding`.
5. If external security or regression systems produce exploit or browser evidence, record that through `ck_regression_result` when it affects release readiness.
6. Summarize blockers, warnings, and follow-up proof requirements.
