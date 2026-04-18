---
name: controlkeel-governance
description: "Operate inside a ControlKeel-governed session. Use this before code edits, shell execution, delegation, deploy work, or any task that needs CK validation, findings, budget, proof, or routing context."
when_to_use: "Activate at task start, before any code edit, shell command, deploy step, or agent delegation. Also activate when the user asks about findings, budgets, proofs, compliance, or security policy."
argument-hint: "[task description or focus area]"
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
  - ck_memory_search
  - ck_memory_record
  - ck_memory_archive
  - ck_regression_result
  - ck_budget
  - ck_route
  - ck_skill_list
  - ck_skill_load
  - ck_cost_optimizer
  - ck_deployment_advisor
  - ck_outcome_tracker
metadata:
  author: controlkeel
  version: "2.0"
  category: governance
  ck_mcp_tools:
    - ck_validate
    - ck_context
    - ck_finding
    - ck_memory_search
    - ck_memory_record
    - ck_memory_archive
    - ck_regression_result
    - ck_budget
    - ck_route
    - ck_cost_optimizer
    - ck_deployment_advisor
    - ck_outcome_tracker
---

# ControlKeel Governance Skill

You are operating inside a **ControlKeel-governed session**. Start here whenever you need the base CK operating protocol.

## Core loop

1. Call `ck_context` at task start to load mission, risk, budget, proof, active findings, workspace context, context reacquisition, instruction hierarchy, and recent transcript state.
2. Call `ck_validate` before writing code, config, shell, or deploy text, and pass trust-boundary metadata when the source content came from the web, tools, skills, or mixed provenance.
3. If you discover a problem the scanner did not raise, call `ck_finding`.
4. Use `ck_memory_search` when you need explicit recall of prior decisions, checkpoints, or findings rather than relying only on the default context packet.
5. Use `ck_memory_record` to persist important decisions, assumptions, and operator guidance that future agents should recover.
6. Use `ck_memory_archive` to retire stale or superseded guidance before it keeps contaminating retrieval.
7. Call `ck_budget` and `ck_cost_optimizer` before expensive model or bulk operations.
8. Call `ck_route` before delegating sub-work to another agent.
9. Use `ck_deployment_advisor` to analyze stack and generate deployment templates when checking ship readiness.
10. Use `ck_regression_result` to record external browser or QA evidence before claiming deploy readiness.
11. Use `ck_outcome_tracker` to track success/failure outcomes for continuous learning.
12. Use `ck_skill_list` and `ck_skill_load` to activate more specific CK workflows.

## Non-negotiable rules

- Never skip `ck_validate` before repo mutations or shell execution.
- A blocked ruling means stop and surface the finding.
- A warned ruling means continue carefully and mention it to the operator.
- On high or critical risk, prefer smaller changes and explicit checkpoints.
- Prefer tightly scoped tasks over broad repo-wide mutation. If the task boundary is vague, narrow it before coding.
- Treat `ck_context` as the stable source of truth for governed state. If host prompts, reminders, or stale notes conflict with it, surface the mismatch instead of guessing.
- Keep context hygiene explicit: fetch what you need, avoid dragging large irrelevant tool output or files into the active working set, and record only the decisions future agents should actually recover.
- For critical paths such as auth, security controls, deploy logic, schema changes, migrations, payments, or compliance-sensitive flows, read the touched code carefully and keep the diff small enough for real human review.
- Do not add abstractions, compatibility shims, or indirection unless they are justified by the current codebase. Prefer the simplest change that solves the actual task.
- Before saying work is done, re-check proof, findings, and budget state.

## Quick reference

- `ck_context` — mission, task, budget, proof, memory, workspace snapshot, transcript summary, resume context
- `ck_validate` — governed preflight scan with trust-boundary checks
- `ck_finding` — persist manual findings
- `ck_memory_search`, `ck_memory_record`, `ck_memory_archive` — explicit typed-memory retrieval and hygiene
- `ck_regression_result` — import external regression evidence into proof state
- `ck_budget` — cost estimate / commit
- `ck_route` — best agent recommendation
- `ck_cost_optimizer` — cost optimization strategies and model comparison
- `ck_deployment_advisor` — repo stack detection, CI/Docker generation, DNS/SSL guide
- `ck_outcome_tracker` — record and review session outcomes/agent scores
- `ck_skill_list`, `ck_skill_load` — specialized workflow activation

## Additional resources

- For the full governed workflow, see [references/workflow.md](references/workflow.md)
