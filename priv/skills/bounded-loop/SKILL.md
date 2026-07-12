---
name: bounded-loop
description: "Run objective, repeatable improvement work under an immutable verifier and hard iteration, cost, time, and no-progress limits. Use for approved experiments with an automated metric and sandboxed worker."
when_to_use: "Activate only when the task repeats, has an objective automated verifier, has an approved mutable path boundary, and can afford bounded retries. Do not use for one-off work, subjective self-grading, or critical changes without human review."
argument-hint: "[approved task and objective metric]"
disable-model-invocation: true
license: Apache-2.0
compatibility: [codex, claude-standalone, claude-plugin, copilot-plugin, github-repo, open-standard, cursor-native, opencode-native]
result-schema:
  type: object
  required: [status, contract_id, iteration_count, cost_cents, proof]
  properties:
    status: {type: string, enum: [active, awaiting_review, succeeded, stopped, blocked]}
    contract_id: {type: integer}
    iteration_count: {type: integer}
    cost_cents: {type: integer}
    proof: {type: array, items: {type: string}}
metadata:
  author: controlkeel
  version: "1.0"
  category: execution
  ck_mcp_tools: [ck_context, ck_budget, ck_loop, ck_validate, ck_rollback, ck_review_submit]
---

# Bounded Loop

Use a loop only when an external verifier can reject the worker's result. The worker never edits the verifier, defines a new success metric, or decides that its own output is good enough.

## Protocol

1. Obtain approval for the artifact class, objective, mutable paths, verifier paths and command, metric direction and target, allowed sandbox adapters, ephemeral-environment requirement, and hard limits.
2. Create the contract with `ck_loop`. Treat the persisted verifier hashes and objective as immutable.
3. Create an audited rollback checkpoint before each worker iteration.
4. Run the worker through the approved sandbox and restrict changes to the contract's mutable paths.
5. Use a fresh sandbox environment for every iteration. Record its provider-neutral environment ID, metric, pass/fail result, cost, hypothesis, mechanism changed, observed effect, and documentation impact with `ck_loop`.
6. On `accept`, keep the candidate and continue. Whenever the decision returns `rollback_required: true`, use `ck_rollback` even if the loop also stopped or blocked. On `awaiting_review`, obtain an independent diff or completion review and call `ck_loop` in `promote` mode. On `stopped` or `blocked`, stop immediately and report the reason.
7. Preserve iteration evidence in CK checkpoints. Do not rewrite history or hide failed experiments.

## Artifact longevity

Classify every contract as `ephemeral_experiment`, `mechanical_transformation`, `research`, `security_triage`, or `lasting_code`. Do not misclassify production code as an experiment to bypass review.

`lasting_code` contracts must freeze invariant boundaries, allowed and forbidden semantic changes, structural complexity budgets, machine-independence requirements, a local-defense limit, and mandatory human promotion. Every iteration must provide verifier-backed invariant effect, complexity deltas, and machine-independence evidence plus a human-readable call graph, diagnosis path, rollback path, and maintenance path that does not depend on model access.

The contract also declares `review_risk` (`standard`, `high`, or `critical`) and required review personas. Worker and reviewer identities must reference CK invocation records for the same session and task. CK derives provider, display model, and canonical provider-issued model ID from those persisted invocation records rather than trusting promotion or review payload labels. Every reviewer must be a different agent; high-risk work needs at least one different canonical model ID; critical work permits no matching canonical model ID. Missing required personas or trusted invocation provenance blocks promotion.

A better headline metric does not override these controls. Unknown invariant effects, machine-dependence, complexity excess, and added local defenses are rejected; repeated local defenses stop the loop. Prefer making bad states unrepresentable over adding another fallback.

When `lasting_code` reaches its target, attach a structured promotion packet naming the changed behavior, declared owning invariant, bad state made impossible, fallbacks removed, affected interfaces, path-and-line code/test citations, deterministic test/build/diagnosis/rollback commands, and durable documentation paths. The exact packet is frozen into the awaiting-review checkpoint.

CK resolves every citation and documentation file inside `project_root`, validates cited line ranges, and freezes their content hashes at target time. Promotion fails if referenced evidence is missing, changed, replaced by a symlink, or no longer matches the reviewed packet. Regenerate evidence and obtain a new review instead of overriding staleness.

Promotion requires an independent reviewer to bind their review to that checkpoint and affirm that the architecture is understandable, complexity is proportional, invariants are mechanically enforced, ownership is accepted without the originating agent, and lasting-code scrutiny is justified. Missing or false attestations block promotion.

For an approved in-process orchestration, `ControlKeel.Runtime.BoundedLoopCoordinator` can compose explicit worker, verifier, and rollback adapters. It has no default worker or verifier, does not schedule itself, and stops on any adapter error or CK terminal decision.

## Hard boundaries

- Never use model self-scores as the objective metric.
- Never modify verifier paths, contract limits, policy, or target after the loop starts.
- Never bypass a blocked finding, exhausted budget, deadline, iteration limit, or no-progress limit.
- Never reuse a sandbox environment across iterations or promote metric success without an independent approved review.
- Never let an outer loop inject code into the verifier or controller.
- Never commit, push, merge, publish, or deploy without the normal CK review gates.
- Never promote `lasting_code` that cannot be tested, diagnosed, rolled back, and maintained without an LLM.

## Completion

Return the declared schema and cite verifier output, accepted iteration checkpoints, and the final review. A higher metric without an unchanged verifier is not proof.
