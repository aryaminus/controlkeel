---
name: controlkeel-governance
description: "Operate inside a ControlKeel-governed session. Use this before code edits, shell execution, delegation, deploy work, or any task that needs CK validation, findings, budget, proof, or routing context."
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
allowed-tools:
  - ck_validate
  - ck_context
  - ck_finding
  - ck_budget
  - ck_route
  - ck_skill_list
  - ck_skill_load
metadata:
  author: controlkeel
  version: "2.0"
  category: governance
  ck_mcp_tools:
    - ck_validate
    - ck_context
    - ck_finding
    - ck_budget
    - ck_route
---

# ControlKeel Governance Skill

You are operating inside a **ControlKeel-governed session**. Start here whenever you need the base CK operating protocol.

## Core loop

1. Call `ck_context` at task start to load mission, risk, budget, proof, and active findings.
2. Call `ck_validate` before writing code, config, shell, or deploy text.
3. If you discover a problem the scanner did not raise, call `ck_finding`.
4. Call `ck_budget` before expensive model or bulk operations.
5. Call `ck_route` before delegating sub-work to another agent.
6. Use `ck_skill_list` and `ck_skill_load` to activate more specific CK workflows.

## Non-negotiable rules

- Never skip `ck_validate` before repo mutations or shell execution.
- A blocked ruling means stop and surface the finding.
- A warned ruling means continue carefully and mention it to the operator.
- On high or critical risk, prefer smaller changes and explicit checkpoints.
- Before saying work is done, re-check proof, findings, and budget state.

## Quick reference

- `ck_context` — mission, task, budget, proof, memory
- `ck_validate` — governed preflight scan
- `ck_finding` — persist manual findings
- `ck_budget` — cost estimate / commit
- `ck_route` — best agent recommendation
- `ck_skill_list`, `ck_skill_load` — specialized workflow activation

## Additional resources

- For the full governed workflow, see [references/workflow.md](references/workflow.md)
