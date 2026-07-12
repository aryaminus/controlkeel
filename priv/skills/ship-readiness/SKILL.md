---
name: ship-readiness
description: "Check install-to-first-finding metrics, funnel stage, findings state, proofs, and approvals before calling a session ready to ship."
when_to_use: "Use before declaring a release, PR, or feature done. Activate when the user says 'ready to ship', 'done', 'merge this', or asks to verify completeness."
argument-hint: "[feature, PR, or release to check]"
disable-model-invocation: true
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
  - cline-native
  - cursor-native
  - windsurf-native
  - continue-native
  - letta-code-native
  - pi-native
  - roo-native
  - goose-native
  - opencode-native
  - gemini-cli-native
  - kiro-native
  - kilo-native
  - amp-native
  - augment-native
  - hermes-native
  - multica-native
  - openclaw-native
  - devin-terminal-native
  - warp-native
  - droid-bundle
  - forge-acp
metadata:
  author: controlkeel
  version: "2.0"
  category: release
  ck_mcp_tools:
    - ck_observability
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

## Observability readiness

Before calling a feature ready, check whether relevant local observability evidence exists. Use `ck_observability` reports for `benchmark_history` and `promotions` to summarize readiness, uncovered scenarios, missed runs, and advisory promotion candidates. A ready advisory candidate is not a policy/router/prompt promotion; it still requires explicit human review.

## Additional resources

- [Release checklist](references/release-checklist.md)


Before calling a session ready to ship, inspect `ck_observability` with `report: "loop_status"` when available. Treat it as read-only evidence: unresolved blockers, uncovered observability benchmarks, or non-ready promotion candidates mean the operator should keep the release human-gated.
