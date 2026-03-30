---
name: cost-optimization
description: "Keep a governed session within budget. Use this before long-running agent work, bulk processing, or any task where spend pressure could change the plan."
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
  category: budget
  ck_mcp_tools:
    - ck_budget
    - ck_context
    - ck_route
    - ck_cost_optimizer
---

# Cost Optimization Skill

## Budget protocol

1. Estimate before expensive work with `ck_budget`.
2. Prefer smaller checkpoints over one large call when spend is uncertain.
3. Use `ck_route` to prefer cheaper valid agents when quality permits.
4. When the budget is low, reduce scope and escalate to the human early.
5. Commit actual usage after completion if your harness is responsible for spend recording.
6. Use `ck_cost_optimizer` to discover savings models, caching strategies, and local model alternatives.

## Additional resources

- For estimation, warning thresholds, and split strategies, see [references/budget-playbook.md](references/budget-playbook.md)
