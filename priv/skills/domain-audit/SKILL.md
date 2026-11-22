---
name: domain-audit
description: "DEPRECATED — use `security-review` instead (it now covers all domain-pack audits — HR, legal, marketing, sales, real-estate, government, insurance, logistics, manufacturing, e-commerce, nonprofit). Kept as a thin alias so `ck_skill_list` for those domains still surfaces `security-review`."
when_to_use: "Do NOT invoke this skill directly — invoke `security-review`, which runs the domain-pack audit as its policy/domain-pack layer. This file exists only so keyword search for HR, legal, marketing, sales, government, etc. routes to the consolidated `security-review` path."
argument-hint: "[use security-review instead]"
license: Apache-2.0
redirect_to: security-review
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
  - antigravity-cli-native
  - kiro-native
  - kilo-native
  - amp-native
  - augment-native
  - devin-terminal-native
  - warp-native
  - droid-bundle
metadata:
  author: controlkeel
  version: "2.0"
  category: domain
  ck_mcp_tools:
    - ck_context
    - ck_finding
  deprecated: true
  superseded_by: security-review
---

# Domain Audit Skill — alias

> **This skill has moved.** Use `security-review` — it runs the same domain-pack
> audit as its policy/domain-pack layer. This file is a thin keyword alias so
> search for `HR`, `legal`, `marketing`, `sales`, `government`, `insurance`,
> `logistics`, `manufacturing`, `e-commerce`, or `nonprofit` still surfaces
> the consolidated path.
