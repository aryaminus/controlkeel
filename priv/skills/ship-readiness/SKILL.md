---
name: ship-readiness
description: "Check install-to-first-finding metrics, funnel stage, findings state, proofs, and approvals before calling a session ready to ship."
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
  category: release
  ck_mcp_tools:
    - ck_context
    - ck_deployment_advisor
---

# Ship Readiness Skill

Use this skill when the operator asks whether a mission or session is ready for release.

## Workflow

1. Check session metrics and current funnel stage.
2. Verify there are no unresolved blockers.
3. Confirm proof state and rollback guidance.
4. Summarize approvals, rejections, and any remaining human work.
5. Provide automatic deployment resources via `ck_deployment_advisor` (Dockerize, CI pipes) for the relevant stack (Phoenix, etc.).

## Additional resources

- [Release checklist](references/release-checklist.md)
