# Local Observability Feedback Loop

ControlKeel's observability loop turns governed evidence into reviewed regression protection. It is local-first and human-gated: it can propose evals, benchmark drafts, and promotion candidates, but it does not automatically rewrite policy, router, prompt, skill, or autofix artifacts.

## How the loop closes

The observability loop is a closed feedback loop, not a logbook:

1. **Outcome auto-emission** — deploy readiness, security scan, regression, and prompt-approval outcomes auto-emit to `OutcomeTracker` with metadata linking back to the shipping decision. No manual call required.
2. **Eval candidate generation** — recurring failure patterns cluster into eval candidates from real trace packets, not paraphrases.
3. **Benchmark drafts** — eval candidates generate benchmark drafts with bounded real trace evidence from `trace_improvement_packet`.
4. **Lifecycle closure** — benchmark run results automatically archive the originating eval candidate when all results matched expected, or reopen it when any result missed. This means the eval backlog self-maintains: passed candidates close, failed candidates stay open for investigation.
5. **Skill evolution** — `ck_skill_evolution` synthesizes from traces and failure clusters. Install mode materializes generated drafts into `.agents/skills/` under the project root, so evolved skills re-enter the catalog without manual copy-paste.

## Workflow

```bash
controlkeel obs status
controlkeel obs problems
controlkeel obs recommend

controlkeel obs evals
controlkeel obs evals save
controlkeel obs evals persisted

controlkeel obs benchmarks draft
controlkeel obs benchmarks drafts
controlkeel obs benchmarks approve <draft-id>
controlkeel obs benchmarks materialize

controlkeel obs benchmarks run --dry-run --subjects controlkeel_validate
controlkeel obs benchmarks run --execute --suite <observability-suite> --subjects controlkeel_validate

controlkeel obs benchmarks history
controlkeel obs regressions
controlkeel obs promotions
```

## What belongs here

The observability loop owns the **evidence lifecycle**:

1. inspect sessions, timelines, costs, memory quality, and recurring problems
2. cluster repeated findings or failures into eval candidates
3. draft benchmark scenarios for human review
4. materialize approved drafts into benchmark suites
5. run benchmarks explicitly
6. inspect promotion readiness and regressions

Benchmark scoring, scenario metadata, split discipline, and claim wording live in [benchmarks.md](benchmarks.md).

## Signals that should feed the loop

Useful signals include:

- validation failures, blocked findings, and repeated review comments
- tool errors, retries, timeouts, loops, and unexpected bypasses
- cost, latency, token, and context-bloat spikes
- capability-gap reports and user frustration signals
- positive patterns worth preserving

Signals should become findings, trace packets, failure clusters, eval candidates, benchmark drafts, or review packets. They should not directly mutate prompts, tools, policies, routers, or skills.

## Trace boundaries

Trace evidence should make debugging faster without turning raw payloads into uncontrolled context:

- prefer identifiers, versions, counts, hashes, durations, and coarse labels over raw prompts or secrets
- include model, prompt, tool, policy, evaluator, and rubric versions when they affect behavior
- store large artifacts by reference with integrity hashes
- keep raw payloads in redacted proof artifacts or local trace viewers when possible

External trace viewers are optional evidence sources. CK owns governed summaries, redaction, findings, eval candidates, benchmark evidence, and human-gated promotion.

## Safety boundaries

- `obs evals save` stores local advisory eval candidate records only.
- `obs benchmarks draft` creates local draft scenarios only.
- `obs benchmarks approve|reject|archive` changes only local draft review state.
- `obs benchmarks materialize` creates local `Benchmark.Suite` and `Benchmark.Scenario` records; it does not run benchmarks.
- `obs benchmarks run --dry-run` is non-mutating preview.
- `obs benchmarks run --execute` records benchmark execution through the local benchmark runner.
- `obs promotions` is advisory reporting only.

## Local telemetry snapshots

Use local envelopes when you need to move or inspect observability evidence without mutating live sessions:

```bash
controlkeel obs export <session-id>
controlkeel obs import <file> --dry-run
controlkeel obs import <file> --persist
controlkeel obs imports
```

Persisted imports are deduplicated snapshots. They do not rewrite sessions, findings, or memory.

## Opt-in telemetry sync levels

Telemetry sync is off by default. When teams need shared observability across instances, use the narrowest useful level:

| Level | What syncs | When to use |
| --- | --- | --- |
| Health | heartbeat, version, workspace ID | fleet monitoring; no governance content |
| Governance metadata | finding counts, review status, budget summaries | team dashboards; no source code or diffs |
| Evidence sync | redacted proofs, reviews, memory citations | cross-host coordination |
| Full enterprise audit | redacted transcripts, benchmark results, policy change history | regulated audit needs |

The local loop works without telemetry sync. Sync must apply redaction before data leaves the node and must not auto-escalate between levels.

## Regression evidence and memory

External regression results recorded through `ck_regression_result` produce two artifacts:
1. An **invocation** (source: `external_qa`, tool: `regression_test`) consumed by proof bundle scoring and deploy-readiness gates.
2. A **regression memory record** (record_type: `regression`) retrievable through `ck_memory_search` with `record_type: "regression"`.

This means regression evidence is both proof-consumable (for the current task) and memory-retrievable (for future agents and sessions).

## Agent-facing use

Agents can consume observability through `ck_observability`, `ck_failure_clusters`, `ck_skill_evolution`, and `ck_context_pack`, but their outputs remain advisory. The goal is continual learning that is explicit, reviewable, and benchmarked before promotion.

`ck_context` surfaces the improvement loop bottleneck and recommended next step automatically — the agent does not need to call observability tools explicitly to see what to do next.
