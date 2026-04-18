---
name: policy-training
description: "Train, inspect, promote, and archive ControlKeel router and budget-hint policy artifacts. Use this only for operator-initiated policy work."
when_to_use: "Activate when the user explicitly requests policy training, policy promotion, or policy artifact management. Do not activate for general governance queries."
argument-hint: "[policy artifact or training dataset]"
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
disable-model-invocation: true
metadata:
  author: controlkeel
  version: "2.0"
  category: policy
  ck_mcp_tools:
    - ck_outcome_tracker
---

# Policy Training Skill

Use this skill only when the task is offline policy training or artifact promotion.

## Workflow

1. Confirm whether you are training `router` or `budget_hint`.
2. Use public and held-out benchmark data appropriately.
3. Review promotion gates and never weaken deterministic controls.
4. Summarize held-out metrics against the heuristic baseline before promotion.
5. Consider real-world success inputs using `ck_outcome_tracker` (leaderboards, recorded session outcomes).

## Additional resources

- [Promotion rules](references/promotion-rules.md)
