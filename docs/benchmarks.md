# ControlKeel Benchmarks

ControlKeel benchmarks test whether a governed change improved a concrete agent workflow. Keep benchmark claims bounded to the suite, subject, scenario count, scorer, and caveats.

## Claim discipline

Good claims:

- "Direct deterministic validation produced findings on 12/12 curated risky fixtures in `host_comparison_v1`; 9/12 were hard blocks and 9/12 hit the expected rule."
- "Bounded active governance used roughly half the tokens of exhaustive active governance on the same suite."
- "This promotion improved held-out catch rate without increasing false blocks on the benign baseline."

Bad claims:

- "CK makes agents safe" without a suite and scoring definition.
- "CK reduces cost by X%" when the run only measured tokens or latency.
- "This model is better" when prompt, tool set, policy, and evaluator changed at the same time.

The bar is reproducibility: baseline, candidate, one changed variable, held-out split, and rollback path.

## Public evidence checklist

When using benchmark results in user-facing material, publish enough context for a skeptical user to reproduce or falsify the claim:

- suite slug and version
- scenario count and split summary (`public` vs `held_out`)
- subject ids, subject type, and baseline subject
- ControlKeel version, policy version, prompt/model/tool versions when applicable
- scorer type (`deterministic`, `llm_judge`, or `human_golden`) and evaluator version
- catch rate, block rate, expected-rule hit rate, and false-positive rate from a paired benign suite
- latency, token, and cost measurements when the claim mentions speed or cost; include cost source (`provider_billing`, `host_json`, `price_table_estimate`, or `unavailable`)
- export artifact id or file path plus rollback criteria

Recommended public bundle:

1. Run `host_comparison_v1` to show risky generated-output handling across governed and ungoverned subjects.
2. Run `benign_baseline_v1` with the same subjects to disclose false positives and false blocks.
3. Keep `policy_holdout_v1` internal for promotion gates; summarize only aggregate held-out status unless the operator intentionally publishes it.

## Built-in suites and value metric

CK's built-in suite bundle is the versioned fixture set:

- `host_comparison_v1` — curated, synthetic host-shaped risky artifacts for deterministic policy-enforcement lift. These are not observed host runs.
- `vibe_failures_v1` — common vibe-coding failures for deterministic regression checks.
- `benign_baseline_v1` — paired safe outputs for false-positive and false-block disclosure.
- `domain_expansion_v1` / `domain_expansion_v2` — domain-pack coverage for regulated and operations-heavy workflows.
- `policy_holdout_v1` — internal held-out promotion gate; do not tune on it.

The default value metric is **catch-rate lift vs no CK policy gate**, paired with benign false-positive disclosure:

```bash
controlkeel benchmark run \
  --suite host_comparison_v1 \
  --subjects null_policy_baseline,controlkeel_validate \
  --baseline-subject null_policy_baseline

controlkeel benchmark compare <run-id>
controlkeel benchmark compare <run-id> --json
controlkeel benchmark export <run-id> --format json
```

`null_policy_baseline` is intentionally not a competitor. It is a null policy baseline: the generated artifact proceeds unchanged without a ControlKeel gate. Use it only for deterministic with-vs-without policy-gate evidence before a team configures Copilot, OpenCode, Claude, Codex, or another external subject.

For VC/YC-style summaries, report a compact scoreboard:

| Metric | Meaning |
| --- | --- |
| Completion rate | Percentage of scenario runs that reached a completed result without timing out or staying pending. |
| Catch-rate lift | Percentage-point increase in risky scenarios with findings vs the null policy baseline. |
| Block-rate lift | Percentage-point increase in hard blocks for scenarios expected to stop. |
| Expected-rule lift | Percentage-point increase in expected policy-rule hits. |
| Benign false-positive rate | Findings on paired safe scenarios; must stay visible. |
| Median latency / overhead | Cost of governance, only when measured for the subject. |
| Tokens and cost per completed task | Spend normalized by successful task, not raw spend alone. |
| Tool-call and CK tool-call rate | Trajectory evidence showing whether an agent used tools, and whether it actually used CK when available. |

Example investor-safe wording:

> On `host_comparison_v1`, ControlKeel improved risky-output catch rate by `<N>` percentage points versus no policy gate. On the paired benign suite, false-positive rate was `<FPR>`. This demonstrates measurable policy-enforcement lift for the named benchmark, not universal agent safety.

### Historical local snapshot

The following numbers are a historical local snapshot from 2026-06-05 with ControlKeel `0.3.45` using deterministic validation only. They are reproducible without provider keys on that version and should be treated as an archived proof baseline, not current product evidence or a universal safety claim. Rerun the suite on the current version before making external claims.

Risky suite: `host_comparison_v1` v1, 12 public risky scenarios, subjects `null_policy_baseline,controlkeel_validate`, baseline `null_policy_baseline`.

| Subject | Catch | Block | Expected-rule hit | TPR | Median validation time | Provider tokens | Est. provider cost |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `null_policy_baseline` | 0/12 | 0/12 | 0/12 | 0.000 | 0 ms | 0 | $0 |
| `controlkeel_validate` | 12/12 | 9/12 | 9/12 | 1.000 | 52 ms | 0 | $0 |

Paired benign suite: `benign_baseline_v1` v1, 10 public safe scenarios.

| Subject | Catch | Block | Expected-rule hit | FPR | Median validation time | Provider tokens | Est. provider cost |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `null_policy_baseline` | 0/10 | 0/10 | 10/10 | 0.000 | 0 ms | 0 | $0 |
| `controlkeel_validate` | 0/10 | 0/10 | 10/10 | 0.000 | 42 ms | 0 | $0 |

Bounded historical headline from this snapshot:

> CK added +100 percentage points of any-finding deterministic policy-gate catch rate versus the null baseline on `host_comparison_v1`, while preserving 0.000 FPR and 0 false blocks on the paired benign suite, with 0 provider tokens in this archived local run.

For external competitors or model-backed subjects, keep the same columns and add provider tokens plus cost source when available. A competitor can plug in through `manual_import` or `shell` subjects and compete directly against `controlkeel_validate` on the same built-in suites.

## Agent-host LLM benchmark protocol (OpenCode, Claude Code, and other hosts)

Deterministic policy-gate evidence answers: "Does CK catch risky artifacts cheaply?" Agent-host evidence answers a different question: "Does a real coding agent using CK produce safer work for the cost/time it spends?" Keep these tables separate.

The protocol below is host-agnostic. It is documented for OpenCode and Claude Code (Sonnet/Opus), and the same five steps apply to Copilot, Codex, Gemini, or any future host: the only credible comparison is the **same host and model run twice** — once with ControlKeel disabled (`pure`) and once with ControlKeel available and bounded (`ck-bounded`) — so exactly one variable changes.

Industry agent/MCP evals generally score three layers: end-to-end completion, trajectory/action quality, and operational efficiency. For CK this maps to completion rate and unsafe-final-output rate; tool-call count, CK tool-call rate, and tool calls per completed task; plus latency, tokens, cost, and cost per completed task. These are the metrics emitted by `benchmark compare` so a host with CK can be compared against the same host without CK.

This mirrors how current MCP/tool-use eval work is structured: MCP-Bench, MCP-AgentBench/MCP-Eval, MCP-Universe/MCPMark, tau-bench-style agent environments, and production eval platforms such as Promptfoo, Braintrust, LangSmith/Langfuse, Weave, DeepEval, and OpenAI Evals all separate final task success from trajectory/tool-use diagnostics and operational spend. The common denominator is: same golden task, same subject matrix, trace capture, deterministic checks where possible, tool-call/argument correctness where applicable, latency, tokens, and cost per successful task.

Use this protocol for OpenCode, Claude Code, and for any future competitor:

1. Choose the same golden suite and split for every subject.
2. Record host, model, CK mode, prompt version, CK version, and policy version.
3. Capture token/cost/time before and after each scenario from the host telemetry (`opencode stats --models --project ""`, `opencode export <sessionID>`, or provider billing logs).
4. Import the final artifact plus telemetry into the benchmark run.
5. Report both quality and efficiency. Do not promote a higher-quality run if it is too slow or too expensive for the approved envelope.

Recommended subject matrix for OpenCode:

These subject IDs are not built-in. They are external subjects configured via `controlkeel/benchmark_subjects.json` in the project root. `controlkeel_validate` is the only built-in subject in this matrix.

| Subject | Purpose | CK availability |
| --- | --- | --- |
| `opencode_pure_manual` | Raw OpenCode with no CK attachment/plugin/MCP. | none |
| `opencode_ck_manual` | OpenCode with CK attached and available. | passive/tool-available |
| `opencode_ck_bounded_manual` | OpenCode instructed to call CK context + validation once, then stop. | bounded active |
| `controlkeel_validate` | Deterministic CK scanner; no model. | direct policy gate |

Run skeleton:

```bash
# Create result slots for the same suite and subjects.
controlkeel benchmark run \
  --suite host_comparison_v1 \
  --subjects opencode_pure_manual,opencode_ck_manual,opencode_ck_bounded_manual,controlkeel_validate \
  --baseline-subject opencode_pure_manual

# For each manual subject and scenario, import the generated final artifact plus telemetry.
controlkeel benchmark import <run-id> opencode_ck_bounded_manual ./artifacts/opencode_ck_bounded/<scenario>.json

# Compare quality, time, tokens, and cost.
controlkeel benchmark compare <run-id>
controlkeel benchmark compare <run-id> --json
```

Recommended subject matrix for Claude Code:

These subject IDs are external shell subjects configured via `controlkeel/benchmark_subjects.json`. `controlkeel_validate` is the only built-in subject in this matrix.

| Subject | Purpose | CK availability |
| --- | --- | --- |
| `claude_pure_shell` | Claude Code with ControlKeel fully disabled (no MCP, no project settings). | none |
| `claude_ck_bounded_shell` | Claude Code + the same model, ControlKeel MCP available, one context+validation pass. | bounded active |
| `controlkeel_validate` | Deterministic CK scanner; no model. | direct policy gate |

Automated run skeleton (shell wrapper, no manual import):

```bash
# The shell subjects run Claude Code directly and emit token/cost/tool telemetry.
# Prerequisites: `claude` CLI installed and authenticated; for the bounded arm,
# the ControlKeel MCP server attached to this project.
CLAUDE_BENCHMARK_MODEL=<pin-a-current-claude-model> \
controlkeel benchmark run \
  --suite host_comparison_v1 \
  --subjects claude_pure_shell,claude_ck_bounded_shell,controlkeel_validate \
  --baseline-subject claude_pure_shell

controlkeel benchmark compare <run-id>
controlkeel benchmark compare <run-id> --json
```

The OpenCode equivalents (`opencode_pure_shell`, `opencode_ck_bounded_shell`) follow the same shape. Use the manual-import flow below only for hosts without a shell wrapper, or when you must capture provider billing that the host JSON does not expose.

Manual import payload shape:

```json
{
  "scenario_slug": "copilot_inline_stripe_key",
  "content": "<final code or final review artifact>",
  "path": "config/payments.py",
  "kind": "code",
  "duration_ms": 23772,
  "metadata": {
    "host": "opencode",
    "model": "operator-chosen-model",
    "ck_mode": "bounded_active",
    "input_tokens": 12345,
    "output_tokens": 2345,
    "total_tokens": 14690,
    "cost_cents": 42,
    "tool_calls": ["ck_context", "ck_validate"],
    "session_export": "artifacts/opencode/session.json"
  }
}
```

Agent-host scorecard columns:

| Column | Why it matters |
| --- | --- |
| Task success | Did the agent finish the requested change/review? |
| Unsafe final-output rate | Findings in the final artifact. Lower is better for generation tasks. |
| CK catch/block rate | Whether CK caught risky artifacts before they moved forward. Higher is better for policy-gate tasks. |
| CK tool-call rate | How often the agent actually used CK when available. |
| Wall time / median latency | Human wait time and CI suitability. |
| Input/output/total tokens | Reproducible model-spend denominator. |
| Cost per accepted task | Investor-friendly efficiency metric; better than cost per token alone. Report only when the cost source is provider billing, host JSON with non-zero cost, or a pinned price table. |

`benchmark compare` makes the with-vs-without difference explicit: each subject line prints absolute median latency, tokens, and cost plus the `Δ` against the baseline subject, and the summary emits an `efficiency_headline` (e.g. `claude_ck_bounded_shell vs claude_pure_shell: +18204 tokens, +8521 ms, +4.2¢ per run.`) alongside a structured `summary.efficiency` block (`token_overhead`, `cost_overhead_cents`, `latency_overhead_ms`, and the per-success variants). The governed arm in the headline is the non-baseline subject doing the most model work. Cost deltas are only meaningful when both subjects carry a real cost source; deterministic CK subjects report 0 model tokens by design, which is the point of the comparison.

Claim template:

> On `<suite>@v<version>`, `<candidate subject>` caught `<caught>/<total>` risky scenarios with `<block_rate>%` hard blocks and `<expected_rule_hit_rate>%` expected-rule hits. On paired benign suite `<benign_suite>`, false-positive rate was `<fpr>` and false-block rate was `<false_block_rate>`. This supports the bounded claim: `<specific behavior improved>`. It does not prove universal agent safety.

Memory/proof claims must be measured separately from policy enforcement. Use proof bundles, memory records, and resume/checkpoint traces to report:

- decisions recovered from typed memory
- repeated failure modes avoided after memory retrieval
- checkpoint or handoff completeness
- unresolved findings carried forward instead of lost across sessions

Do not mix memory/proof improvements into catch-rate claims unless the benchmark scenario explicitly exercises memory retrieval or resume behavior.

## Benchmark lifecycle

1. Mine findings, traces, review comments, support reports, and failure clusters.
2. Classify the failure dimension before choosing the scorer.
3. Draft small, behavior-rich scenarios.
4. Keep optimization and held-out splits explicit.
5. Run baseline and candidate against the same suite.
6. Promote only when quality, safety, latency, and cost stay inside the operating envelope.

Use [observability-feedback-loop.md](observability-feedback-loop.md) for the local evidence-to-draft workflow. This file owns scoring and metadata discipline.

## Subject types

Built-in subjects (available without configuration):

- `null_policy_baseline` — null policy baseline; no CK gate runs and the artifact proceeds unchanged.
- `controlkeel_validate` — direct deterministic validation path.
- `controlkeel_proxy` — proxy-shaped policy scan path; it does not execute provider traffic.

Subject types (for external subjects configured via `controlkeel/benchmark_subjects.json`):

- `manual_import` — awaiting-import run first, then import captured external output.
- `shell` — scriptable subject that writes stdout or files for rescoring. Shell subjects can also write `.controlkeel_metrics.json` in `CONTROLKEEL_BENCHMARK_OUTPUT_DIR`; CK merges that sidecar into result metadata and excludes it from artifact scanning.

The recommended first external comparison is `ControlKeel Validate` vs `OpenCode Manual Import`; it is reproducible without requiring a deeper native integration first.

This repo includes `scripts/benchmark-host.sh` as a starter shell subject wrapper for both OpenCode and Claude Code. It accepts `opencode`, `opencode-pure`, `opencode-ck-bounded`, `claude`, `claude-pure`, and `claude-ck-bounded`. It reads the benchmark prompt/scenario environment variables, runs the host with JSON output, writes the final artifact, and emits `.controlkeel_metrics.json` with best-effort duration, token, cost, and CK tool-call telemetry. The `-pure` arm runs the agent with ControlKeel fully disabled (OpenCode `--pure`; Claude `--strict-mcp-config` with no MCP servers and `--setting-sources user`), and the `-ck-bounded` arm runs the same agent and model with ControlKeel available but capped at one context+validation pass — so the with-vs-without delta isolates a single variable. Treat the wrapper as schema-sensitive: verify it against the installed host version before using model-backed numbers externally.

## Scenario design

Prefer deterministic checks when possible:

- policy, schema, exact-match, capability, and regression assertions
- required citations, expected files, blocked actions, or refusal requirements
- source-shape constraints such as file size, layering, or dependency edges

Use judge-based scoring only for narrow semantic dimensions with rubrics, anchors, constrained labels, and meta-evaluation against human/golden labels.

Keep these eval families separate:

| Family | Use |
| --- | --- |
| Capability eval | Measures a target capability the system is trying to reach. |
| Regression eval | Preserves behavior that already works. |
| Red-team eval | Tests hostile inputs, tool misuse, leakage, or prohibited actions. |
| Persona eval | Scores role-specific output expectations without averaging them away. |
| Premise-refusal eval | Checks whether the agent resists bad assumptions or over-solving. |

## Required metadata

Every scenario should carry enough metadata to explain what changed and why the result matters.

Core fields:

- `eval_source`: `production_trace`, `synthetic`, `review_feedback`, `operator_debrief`, or `red_team`
- `eval_mode`: `deterministic`, `llm_judge`, or `human_golden`
- `failure_dimension`: `correctness`, `faithfulness`, `safety`, `schema`, `groundedness`, or `task_completion`
- `domain_pack`, `task_type`, `artifact_type`, `security_workflow_phase`
- `behavior_tags`
- `baseline_run_id`, `candidate_run_id`, `rollback_target_version`

Version fields:

- `model_version`
- `prompt_version`
- `tool_version`
- `workflow_version`
- `policy_version`
- `evaluator_version`
- `rubric_version`

Signal fields for production-derived evals:

- `signal_source`: `explicit`, `implicit`, `trajectory`, or `self_diagnostic`
- `signal_name`
- `signal_rate_baseline`
- `signal_rate_candidate`
- `feature_flag`, `experiment_id`, `cohort_id`
- `representative_trace_ids`

## Specialized metadata

Persona output:

- `persona_role`
- `output_focus`
- `format_profile`
- `tone_profile`

Red-team:

- `attack_strategy`
- `risk_category`
- `allowed_actions`
- `prohibited_actions`
- `safety_gate_version`

Retrieval quality:

- `search_task_type`
- `retrieval_strategy`
- `orientation_metric`
- `result_presentation`
- `memory_surface`

Runtime experiments:

- `runtime_contract`
- `adapter_contract`
- `tool_encoding`
- `execution_surface`
- `experiment_variable`

Skill activation:

- `expected_skill`
- `activation_signal`
- `false_positive_guard`
- `token_snapshot`

Delegation and subagent surfaces:

- agent identity, role, and authority boundary
- handoff packet completeness
- dependency graph and blocking relationships
- async/background status, event logs, progress, interrupt behavior, and completion receipts

## Split discipline

Built-in scenarios can carry split-aware metadata:

- `public` for reusable suites
- `held_out` for reserved evaluation

Do not tune prompts, policies, or router behavior on held-out scenarios. Promote only when held-out evidence improves without backsliding on safety, false-block, latency, or cost constraints.

## Large artifacts

Treat screenshots, videos, audio, binary reports, PR previews, and UI diffs as referenced artifacts:

- store bytes in object storage or file-backed proof bundles
- keep pointers, metadata, and integrity digests in the run record
- render or inspect them in review surfaces when needed

Do not stuff large binaries into database rows or transcripts.

## Rollout abort threshold

Use benchmark results as release gates for behavior-changing harness work. Abort or require human review if:

- held-out catch rate drops
- benign false-block rate rises
- critical red-team scenarios regress
- latency or token cost exceeds the approved envelope
- scenario diversity or classification evidence is missing

For minority or experimental model integrations, route enough traffic to reach decision-useful evidence instead of relying on tiny proportional samples.

## Web UI quick presets

On `/:org_slug/workspaces/:ws_slug/benchmarks`, Quick presets fill subject and baseline fields for common runs such as OpenCode comparison, ControlKeel validate only, or validate plus governed proxy. The subjects field is a multi-select over the available subjects; the CLI and API still accept comma-separated subject lists. Running a suite is admin/owner only on the workspace page — viewers get a read-only view of the summary, suites catalog, and run history. Completed runs open on the workspace run page `/:org_slug/workspaces/:ws_slug/benchmarks/runs/:id`; the old global `/benchmarks/runs/:id` URL is retired and falls through to the invalid-organization panel.

## Interpretation

Use benchmark results as product evidence, but keep the claim precise:

- name the suite
- name the subjects
- disclose scenario count and split
- distinguish catch rate from block rate
- report latency, token, or cost proxies honestly
- keep false positives visible
- record rollback criteria
