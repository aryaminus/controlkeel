# Governed Workflow

Use this reference with `controlkeel-governance`.

## Start

1. `ck_context` to load mission, task, risk, budget, proof summary, memory hits, workspace snapshot, and recent transcript events.
2. Identify whether the task is implementation, review, compliance, benchmark, or policy work.
3. Load a more specific CK skill if the task has a narrower workflow.

## Before mutations

1. Validate the exact code, config, shell, or text with `ck_validate`.
2. Respect `block` immediately.
3. Note `warn` in your reply and continue carefully.

## During work

1. Keep changes small.
2. Call `ck_budget` before expensive multi-agent or long-context work.
3. Use `ck_route` when another agent would be materially better.
4. Create a `ck_finding` entry for any issue not automatically detected.

## Before completion

1. Re-check active findings.
2. Re-check budget and proof state.
3. If the session is high or critical risk, summarize decisions and unresolved items explicitly.
