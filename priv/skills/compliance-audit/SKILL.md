---
name: compliance-audit
description: "Run a structured compliance audit against active ControlKeel policy packs and domain controls. Use this before shipping regulated data flows, external integrations, or document exports."
when_to_use: "Activate before exporting data, integrating with external services, or when the user asks about compliance, regulatory requirements, GDPR, SOC2, HIPAA, or policy packs."
argument-hint: "[data flow, integration, or domain to audit]"
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
  category: compliance
  ck_mcp_tools:
    - ck_context
    - ck_validate
    - ck_finding
---

# Compliance Audit Skill

## Audit flow

1. Call `ck_context` and confirm the active compliance profile for the session.
2. Review only the pack sections that match the active domain pack and data flows.
3. Use `ck_validate` for concrete snippets and configs when the checklist points to code.
4. Persist each failing control with `ck_finding`.
5. End with packs checked, controls reviewed, blockers, and required approvals.

## Additional resources

- For the full domain-by-domain checklist, see [references/control-matrix.md](references/control-matrix.md)
