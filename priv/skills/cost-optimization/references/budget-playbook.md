# Budget Playbook

## Estimate first

- Use `ck_budget` estimate mode before expensive operations.
- Prefer model-based pricing inputs when you know tokens and model.
- Use explicit `estimated_cost_cents` when the model is unknown.

## Split and checkpoint

- Break long tasks into smaller runs.
- Stop after each step and reassess remaining session and rolling-24h budget.

## Escalation guidance

- If remaining daily budget is tight, pause and ask for approval before the next expensive step.
- If the operation is optional, defer it instead of spending the last budget headroom.

