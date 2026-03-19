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
---

# Security Review Skill

Use this skill before closing a task, approving a proof bundle, or reviewing a risky diff.

## Review flow

1. Call `ck_context` to load the domain pack, risk tier, and open findings.
2. Run `ck_validate` on the relevant code or config slices.
3. Walk the review checklist in [references/review-checklist.md](references/review-checklist.md).
4. Persist any missed issue with `ck_finding`.
5. Summarize blockers, warnings, and follow-up proof requirements.
