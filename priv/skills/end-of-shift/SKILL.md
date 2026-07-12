---
name: end-of-shift
description: "Close a governed work session with validation, proof, findings, budget, digest, learning, and handoff checks. Use when the user asks to wrap up, stop for the day, or leave work ready for another agent."
when_to_use: "Activate only at an explicit session stop point or when the user asks for end-of-shift validation. Do not run expensive full-suite or benchmark work unless project policy or the approved plan requires it."
argument-hint: "[completed work or remaining task]"
disable-model-invocation: true
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
  - cursor-native
  - opencode-native
result-schema:
  type: object
  required: [status, validation, findings, proof, budget, remaining_work]
  properties:
    status: {type: string, enum: [complete, partial, blocked]}
    validation: {type: array, items: {type: string}}
    findings: {type: array, items: {type: string}}
    proof: {type: array, items: {type: string}}
    budget: {type: string}
    remaining_work: {type: array, items: {type: string}}
    handoff_reference: {type: [string, "null"]}
metadata:
  author: controlkeel
  version: "1.0"
  category: execution
  ck_mcp_tools:
    - ck_context
    - ck_git_status
    - ck_git_diff
    - ck_validate
    - ck_budget
    - ck_task
    - ck_session_digest
    - ck_outcome_tracker
    - ck_memory_record
    - ck_checkpoint_create
---

# End of Shift

Close work with enough verified state that the next human or agent can continue without reconstructing the session from chat.

## Workflow

1. Reacquire CK context and inspect git status and diff. Identify untracked artifacts, unrelated changes, unresolved tasks, pending reviews, and active findings.
2. Run the targeted checks required by the changed behavior. Run the project's full completion command only when policy or the approved plan requires it.
3. Validate the final diff and stop on blocked findings. Record warnings with their concrete consequence.
4. Correlate tests, external regression results, and review approvals with the task proof. Do not call an untested or unreviewed path complete.
5. Check budget and record the session outcome. Generate a digest.
6. Persist only durable decisions or reusable lessons. Do not commit raw transcripts, speculative notes, secrets, or duplicated summaries.
7. If work remains, create a checkpoint and use the handoff workflow with explicit next action, blockers, validation state, and allowed scope.

## Stop conditions

- `blocked`: an active blocked finding, failed required check, denied review, or unsafe workspace state remains.
- `partial`: completed work is valid but scoped work remains or required external evidence is unavailable.
- `complete`: required checks pass, findings are dispositioned, proof is present, and no approved-scope work remains.

## Output

Return the declared result schema. Include exact validation commands or proof references, not “tests pass” without evidence.
