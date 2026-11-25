---
name: compliance-audit
description: "DEPRECATED — use `security-review` instead (it now covers all of this — regulated flows, policy packs, domain controls). Kept as a thin alias for search (compliance/GDPR/SOC2/HIPAA) so existing `ck_skill_list` queries still surface `security-review`."
when_to_use: "Do NOT invoke this skill directly — invoke `security-review`, which runs the compliance audit as its policy/domain-pack layer. This file exists only so keyword search for compliance, GDPR, SOC2, HIPAA routes to the consolidated `security-review` path."
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
  category: compliance
  ck_mcp_tools:
    - ck_context
    - ck_validate
    - ck_finding
  deprecated: true
  superseded_by: security-review
---

# Compliance Audit Skill — alias

> **This skill has moved.** Use `security-review` — it runs the same compliance audit
> as its policy/domain-pack layer (active compliance profile → pack sections →
> `ck_validate` → `ck_finding`). This file is a thin keyword alias so search for
> `compliance`, `GDPR`, `SOC2`, `HIPAA` still surfaces the consolidated path.
