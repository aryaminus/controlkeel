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
allowed-tools:
  - ck_validate
  - ck_execute_code
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
    - ck_execute_code
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

## Before new work

For any new feature, fix, or project — before writing plans or code — use the `align` skill to reach shared understanding of the goal, layers, acceptance criteria, and **assumptions**. Surface assumptions explicitly before proceeding to prevent expensive misalignments caught after implementation. Once aligned, use `plan-slice` to decompose the goal into vertical slices with explicit blocking relationships and concrete success criteria before any implementation begins. Planning is always human-in-the-loop; implementation of an approved slice can be AFK.

## Core loop

1. Call `ck_context` at task start to load mission, risk, budget, proof, active findings, workspace context, context reacquisition, instruction hierarchy, and recent transcript state.
2. Call `ck_validate` before writing code, config, shell, or deploy text, and pass trust-boundary metadata when the source content came from the web, tools, skills, or mixed provenance.
3. Use `ck_execute_code` only for generated code that should run inside CK's guarded Docker sandbox; prefer `dry_run` first, and never treat it as local shell access or a network/secrets grant.
4. If you discover a problem the scanner did not raise, call `ck_finding`.
5. Use `ck_memory_search` when you need explicit recall of prior decisions, checkpoints, or findings rather than relying only on the default context packet.
6. Use `ck_memory_record` to persist important decisions, assumptions, and operator guidance that future agents should recover.
7. Use `ck_memory_archive` to retire stale or superseded guidance before it keeps contaminating retrieval.
8. Call `ck_budget` and `ck_cost_optimizer` before expensive model or bulk operations.
9. Delegate only when the user explicitly requests it or an approved plan authorizes it, then call `ck_route` before selecting another agent. Tool availability alone is not a reason to delegate routine work.
10. Use `ck_deployment_advisor` to analyze stack and generate deployment templates when checking ship readiness.
11. Use `ck_regression_result` to record external browser or QA evidence before claiming deploy readiness.
12. Use `ck_outcome_tracker` to track success/failure outcomes for continuous learning.
13. Use `ck_skill_list` and `ck_skill_load` to activate more specific CK workflows.

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

## Invariant Enforcement vs. Local Workarounds

**Critical principle**: Prefer enforcing system invariants over adding local workarounds for bad states.

- **Avoid**: "Make the system work with malformed data" (tolerant readers, fallbacks, recovery logic)
- **Prefer**: "Make malformed data impossible" (validation at write time, strict schemas, invariants)

AI-generated code often sees a local failure and adds local defenses against it. This accumulates complexity and weakens system foundations. Instead:

1. **Identify the invariant**: What should always be true? (e.g., session logs are always valid, user data is always validated)
2. **Enforce at the boundary**: Prevent invalid states from being written, not handle them after the fact
3. **Remove workarounds**: Existing code that handles "impossible" states should be removed after invariant enforcement
4. **Validate patterns**: Use `ck_finding` with category `architecture` and rule `CK-INVARIANT-001` when you see tolerance for bad states

**Examples**:
- ❌ Add fallback reader for corrupted session logs
- ✅ Prevent corrupted session logs from being written (strict validation, checksums)
- ❌ Add migration for malformed user records
- ✅ Enforce schema constraints so malformed records cannot be created
- ❌ Add retry logic for undefined API responses
- ✅ Define strict API contracts and validate responses against them

## Quick reference

- `ck_context` — mission, task, budget, proof, memory, workspace snapshot, transcript summary, resume context
- `ck_validate` — governed preflight scan with trust-boundary checks
- `ck_execute_code` — guarded generated-code execution; Docker sandbox only, local/network/secrets/shell/deploy denied, `dry_run` recommended first
- `ck_finding` — persist manual findings
- `ck_memory_search`, `ck_memory_record`, `ck_memory_archive` — explicit typed-memory retrieval and hygiene
- `ck_regression_result` — import external regression evidence into proof state
- `ck_budget` — cost estimate / commit
- `ck_route` — best agent recommendation
- `ck_cost_optimizer` — cost optimization strategies and model comparison
- `ck_deployment_advisor` — repo stack detection, CI/Docker generation, DNS/SSL guide
- `ck_outcome_tracker` — record and review session outcomes/agent scores
- `ck_skill_list`, `ck_skill_load` — specialized workflow activation
- `align` skill — pre-work alignment interview before any plan or code
- `plan-slice` skill — vertical slice decomposition with blocking relationships and autonomy labels

## Additional resources

- For the full governed workflow, see [references/workflow.md](references/workflow.md)
- For issue and PR validation patterns to combat AI-generated slop, see [docs/issue-pr-validation-guide.md](../../docs/issue-pr-validation-guide.md)
