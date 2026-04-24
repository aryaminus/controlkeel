# Software Laws Opportunities for ControlKeel

Prepared: April 22, 2026
Source: [Laws of Software Engineering](https://lawsofsoftwareengineering.com/)

## Summary

The Laws of Software Engineering list is useful for ControlKeel because it names failure modes that agentic delivery systems repeatedly hit: metric gaming, interface drift, overgrown abstractions, communication mismatches, stale tests, hidden bottlenecks, and overconfident decisions.

ControlKeel already aligns with many of these principles through its current control-plane model:

- explicit work boundaries, execution posture, and runtime recommendation
- review gates, findings, proofs, and ship readiness
- typed integration catalogs and host-specific attach/export paths
- benchmark split discipline and held-out promotion evidence
- budget-aware routing, spend alerts, and outcome tracking
- typed memory, resume packets, workspace snapshots, and trace packets
- human wake-up surfaces for irreversible or high-impact work

The opportunity is not to add a decorative philosophy layer. The opportunity is to turn the best laws into product diagnostics that appear exactly when an operator or agent is about to make a predictable mistake.

## First Shippable Slices

### 1. Goodhart Guardrails

Relevant laws:

- Goodhart's Law
- Pesticide Paradox
- The Map Is Not the Territory
- Confirmation Bias

ControlKeel already uses metrics in Ship Dashboard, Benchmarks, routing, budget, and outcome tracking. Those metrics become dangerous when they are optimized as isolated targets.

Implementation direction:

- Add a `metric_integrity` or `promotion_integrity` check before benchmark/policy/router promotion.
- Require held-out evidence for promoted harness changes, not only public-suite improvements.
- Warn when one scalar score is used without proof diversity, regression checks, or structured trace evidence.
- Surface stale-eval warnings when the same scenario set repeatedly passes without new trace-derived cases.

Likely surfaces:

- `ControlKeel.Benchmark`
- `ControlKeel.PolicyTraining`
- Ship Dashboard
- `ck_skill_evolution`
- benchmark export metadata

Expected finding examples:

- `metrics.goodhart.single_score_promotion`
- `benchmarks.eval_staleness`
- `benchmarks.missing_holdout_evidence`

### 2. Hyrum Parity Checks

Relevant laws:

- Hyrum's Law
- Principle of Least Astonishment
- Postel's Law
- The Law of Leaky Abstractions

CK exposes similar behavior through several surfaces: MCP tools, CLI commands, REST endpoints, web LiveViews, generated plugins, host hooks, and exported runtime bundles. Any observable mismatch can become an accidental contract.

Implementation direction:

- Add parity checks for review IDs, finding payloads, validation decisions, and context fields across CLI, MCP, REST, and web surfaces.
- Promote existing runtime conformance tests into a broader "observable contract" suite.
- Include generated plugin/tool schemas in the parity check so host bundles do not drift from first-party APIs.
- Treat parity gaps as product findings with exact surface pairs and payload fields.

Likely surfaces:

- `ControlKeel.ProtocolInterop`
- `ControlKeel.AgentRuntimes.Registry`
- runtime conformance tests
- generated plugin bundle tests
- support matrix docs

Expected finding examples:

- `contracts.surface_parity.review_id_lookup`
- `contracts.schema_drift.mcp_cli`
- `contracts.plugin_schema_drift`

### 3. Complexity and Drift Budgets

Relevant laws:

- Gall's Law
- Tesler's Law
- Second-System Effect
- YAGNI
- KISS
- Technical Debt
- Broken Windows Theory

CK already reports design-drift signals in workspace context, including very large files and recent edit hotspots. That signal can become a more useful operating budget.

Implementation direction:

- Convert drift signals into severity-scored findings with thresholds for file size, hotspot churn, and repeated plan churn.
- Add "complexity budget" context to `ck_context`, not as a blocker by default but as review pressure.
- When a plan touches a high-drift module, require smaller implementation steps, stronger tests, or a refactor note.
- Distinguish irreducible complexity from accidental complexity so CK does not reward shallow code golf.

Likely surfaces:

- `ControlKeel.WorkspaceContext`
- `ck_context`
- review submission quality scoring
- Ship Dashboard
- Progress Dashboard

Expected finding examples:

- `design.large_file_budget_exceeded`
- `design.hotspot_churn`
- `planning.second_system_risk`

### 4. Ownership and Bus-Factor Signals

Relevant laws:

- Conway's Law
- Bus Factor
- Price's Law
- Ringelmann Effect
- Brooks's Law

Agentic work still inherits team and ownership structure. CK can make those boundaries visible instead of letting delegation look evenly distributed when it is not.

Implementation direction:

- Track concentration of approvals, findings, proof authorship, task ownership, and modified modules.
- Warn when a critical task or release depends on one person, one agent, or one opaque host surface.
- Use task graph edges to show where communication boundaries and architecture boundaries are misaligned.
- For late/high-risk tasks, warn before adding broad parallel delegation that increases coordination cost.

Likely surfaces:

- Mission Control
- task graph state
- Proof Browser metadata
- outcome tracker
- router/delegation recommendations

Expected finding examples:

- `teams.bus_factor.low`
- `teams.approval_concentration`
- `delegation.coordination_overhead`

### 5. Decision Hygiene Prompts

Relevant laws:

- Dunning-Kruger Effect
- Sunk Cost Fallacy
- Inversion
- Occam's Razor
- Hanlon's Razor
- First Principles Thinking

CK should not turn these into generic motivational text. They are useful only when tied to evidence.

Implementation direction:

- Trigger decision prompts when a plan has repeated failed reviews, repeated validation warnings, or rising scope without evidence.
- Ask inversion-style questions in review packets: "What would make this fail in production?" and "What is the smallest reversible step?"
- Warn on overconfident completion packets with weak verification evidence.
- Preserve reviewer notes that choose a simpler explanation or smaller rollback path.

Likely surfaces:

- `ck_review_submit`
- review quality scoring
- proof readiness
- completion packets

Expected finding examples:

- `planning.sunk_cost_signal`
- `review.weak_verification_confidence`
- `planning.scope_without_evidence`

### 6. Bottleneck Reporting

Relevant laws:

- Amdahl's Law
- Gustafson's Law
- Parkinson's Law
- Hofstadter's Law

CK already tracks budgets, task state, findings, reviews, proofs, and outcomes. It can show the serial constraint that is actually limiting delivery.

Implementation direction:

- Add a bottleneck summary to Ship Dashboard and improvement loop output.
- Attribute delay to review wait, unresolved findings, validation runtime, budget exhaustion, flaky tests, provider latency, or unclear scope.
- Compare "more agents" against the serial bottleneck before recommending delegation.
- Keep estimates evidence-based and update them after each run.

Likely surfaces:

- Ship Dashboard
- `ck_context`
- `ck_route`
- `ck_delegate`
- improvement loop summaries

Expected finding examples:

- `delivery.serial_bottleneck.review_wait`
- `delivery.serial_bottleneck.unresolved_findings`
- `delegation.parallelism_limited`

## Laws Already Well Covered

These principles already appear strongly in CK's shipped posture:

- Murphy's Law: validation, findings, destructive command tripwires, rollback expectations
- Boy Scout Rule: guided fixes and review loops
- CAP Theorem and distributed fallacies: explicit runtime/host boundaries and no universal-host claims
- DRY and SOLID: typed shared integration catalogs and protocol surfaces
- Lindy Effect: conservative, code-backed primitives over speculative platform claims
- Premature Optimization and YAGNI: current docs explicitly defer microVMs, autonomous deployment, and self-healing systems

## Recommended Order

1. **Shipped**: Goodhart guardrails — `Benchmark.promotion_integrity_profile/1` and `PolicyTraining.promotion_integrity/1` expose integrity profiles with evidence-channel counts, promotion-blocking policy gates, and diagnostic finding payloads including `benchmarks.single_score_promotion`, `benchmarks.eval_staleness`, `benchmarks.missing_holdout_evidence`, `benchmarks.low_behavior_diversity`, and `benchmarks.missing_classification_evidence`.
2. **Shipped (partial)**: Hyrum parity checks — hosted MCP tool/schema/scope parity is covered in `runtime_conformance_test.exs`. Full cross-surface parity (CLI/REST/web payload parity) and rule IDs `contracts.surface_parity.*`, `contracts.schema_drift.*` remain planned.
3. **Shipped**: Complexity and drift budgets — `WorkspaceContext.complexity_budget/3` produces a severity-scored budget. `WorkspaceContext.complexity_budget_findings/2` emits granular findings: `design.complexity_budget.high|medium`, `design.large_file_budget_exceeded`, `design.hotspot_churn`, and `planning.second_system_risk`.
4. **Shipped**: Bottleneck reporting — `AutonomyLoop.bottleneck_summary/4` and `bottleneck_findings/2` appear in session improvement loops and Ship Dashboard rows with findings `delivery.serial_bottleneck.{unresolved_findings,review_wait,budget_pressure}` and `delegation.coordination_overhead`.
5. **Shipped**: Ownership and bus-factor signals — `AutonomyLoop.ownership_summary/1` and `ownership_findings/2` emit `teams.ownership_concentration`, `teams.bus_factor.low`, and `teams.approval_concentration`.
6. **Shipped**: Decision hygiene — `Mission.decision_hygiene_prompts/4` generates inversion, evidence, sunk-cost, and alternative prompts in review gates. `Mission.decision_hygiene_findings/2` emits structured finding payloads: `planning.sunk_cost_signal`, `planning.scope_without_evidence`, and `review.weak_verification_confidence`.

## Validation Notes

Slices 1, 3, 4, 5, and 6 are fully implemented with dedicated test coverage in:
- `test/controlkeel/benchmark_test.exs` — promotion integrity, single_score_promotion, eval_staleness
- `test/controlkeel/policy_training_test.exs` — policy promotion integrity
- `test/controlkeel/workspace_context_test.exs` — complexity budget, granular drift findings
- `test/controlkeel/autonomy_loop_test.exs` — bottleneck, ownership, bus_factor, coordination
- `test/controlkeel/mission_test.exs` — decision hygiene findings, review gate status

Slice 2 (Hyrum parity) has hosted MCP parity coverage. Cross-surface CLI/REST/web parity checks and the remaining rule IDs (`contracts.surface_parity.*`, `contracts.schema_drift.*`, `delegation.parallelism_limited`) are planned but not yet implemented.

Any future implementation should:
- add tests before exposing a diagnostic as shipped behavior
- keep warnings evidence-backed and source-specific
- avoid blocking work solely because a named law applies; current policy promotion gates block only when required evaluation evidence is missing
