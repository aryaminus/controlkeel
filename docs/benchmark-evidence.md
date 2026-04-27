# Benchmark Evidence & Trust

This document explains ControlKeel's benchmark methodology, how it compares to industry standards, and why the results are trustworthy.

## Methodology

### Classification metrics

ControlKeel uses standard confusion-matrix classification metrics:

- **True Positives (TP)**: Scenarios with dangerous content that CK correctly caught
- **False Positives (FP)**: Benign scenarios that CK incorrectly flagged
- **True Negatives (TN)**: Benign scenarios that CK correctly allowed
- **False Negatives (FN)**: Dangerous scenarios that CK missed

From these, CK computes:

- **TPR (True Positive Rate / Recall)**: TP / (TP + FN) — catch effectiveness
- **FPR (False Positive Rate)**: FP / (FP + TN) — false alarm rate
- **Youden's J**: TPR − FPR — single-number quality metric (1.0 = perfect)

### Paired positive/negative suites

CK ships paired suites for balanced evaluation:

| Suite | Purpose | Scenarios |
|-------|---------|-----------|
| `vibe_failures_v1` | Positive cases (should trigger findings) | 10 unsafe patterns |
| `benign_baseline_v1` | Negative cases (should NOT trigger findings) | 10 safe equivalents |
| `host_comparison_v1` | Cross-host unsafe patterns | 12 common agent failures |

Each benign scenario is paired with a specific unsafe scenario (e.g., `hardcoded_api_key_python_webhook` ↔ `benign_env_credential_loading`). This enables precise TPR/FPR measurement rather than single-metric reporting.

### Split discipline

CK follows the same split discipline used in machine learning evaluation:

- **Public suites** (`vibe_failures_v1`, `benign_baseline_v1`, `host_comparison_v1`, `domain_expansion_v1/v2`): For normal benchmarking and external reporting
- **Held-out suites** (`policy_holdout_v1`): Reserved for policy-artifact promotion gates. Never used for optimization

This prevents overfitting governance rules to the visible test cases.

### Promotion integrity

Every benchmark run computes a `promotion_integrity` profile:

- Are held-out scenarios present?
- Is there sufficient behavior-tag diversity?
- Are classification metrics (TPR/FPR/Youden's J) available?

Policy artifacts cannot be promoted unless these integrity checks pass.

## Comparison with industry tools

### ControlKeel vs Promptfoo

| Dimension | ControlKeel | Promptfoo |
|-----------|------------|-----------|
| Focus | Governance policy enforcement | LLM output quality & security |
| Test format | JSON suites with expected decisions | YAML configs with assertions |
| Scoring | OWASP classification (TP/FP/TN/FN) | Pass/fail with custom graders |
| CI integration | `mix precommit`, CLI pipeline | `npx promptfoo eval` |
| Governance loop | Findings → proofs → policy training | Evaluation results only |
| Multi-host | Native cross-host comparison | Side-by-side model comparison |

### ControlKeel vs Lakera B3

| Dimension | ControlKeel | Lakera B3 |
|-----------|------------|-----------|
| Scope | Code + config governance | LLM input/output security |
| Benchmark source | Hand-curated + trace-promoted | Crowdsourced adversarial |
| Metric model | OWASP classification | Detection rate |
| FPR measurement | Paired benign suite | Separate benign dataset |
| Deployment | Local repo governance | Cloud API gateway |

### ControlKeel vs LangSmith Evaluation

| Dimension | ControlKeel | LangSmith |
|-----------|------------|-----------|
| Focus | Governance policy compliance | Agent trajectory quality |
| Test unit | Single artifact scan | Full agent trace |
| Scoring | Deterministic pattern/rules | LLM-as-judge + heuristics |
| Reproducibility | Fully deterministic | Depends on judge model |
| Policy gates | Block/warn/allow enforcement | Observation only |

### ControlKeel vs OpenAI Evals

| Dimension | ControlKeel | OpenAI Evals |
|-----------|------------|-------------|
| Focus | Governance enforcement | Model quality measurement |
| Scoring | Pattern/rules-based (deterministic) | Model-graded + exact match |
| Provider lock-in | Provider-agnostic | OpenAI API only |
| Production loop | Findings → proofs → policy training | Evaluation datasets only |

## Reproducibility guarantees

1. **Deterministic scoring**: CK's pattern and rule scanners produce identical results for identical input. No LLM-as-judge variance.
2. **Version-locked suites**: Each suite carries a `version` field. Suite content is synced from `priv/benchmarks/*.json` with deterministic ordering.
3. **Subject config hashing**: Each run records a `subject_config_hash` so you can verify the exact subject configuration used.
4. **Export provenance**: JSON exports include `eval_profile`, `classification`, and `promotion_integrity` metadata for full auditability.

## Honest claims policy

- CK reports **catch rate**, **block rate**, **expected-rule hit rate**, **TPR**, **FPR**, and **Youden's J** — not just a single marketing number
- CK explicitly warns when benchmark evidence lacks holdout coverage or behavior diversity
- CK does not claim universal protection. Benchmark results show performance against the specific scenarios in each suite
- CK recommends running the paired benign suite (`benign_baseline_v1`) alongside any positive-result suite for balanced TPR/FPR reporting

## Recommended evidence package

For external reporting, export:

1. One `host_comparison_v1` run with all subjects
2. One `benign_baseline_v1` run for FPR measurement
3. Both exported as CSV or JSON
4. Include the `eval_profile`, `classification`, and `promotion_integrity` sections

```bash
controlkeel benchmark export <HOST_RUN_ID> --format json > evidence-host-comparison.json
controlkeel benchmark export <BENIGN_RUN_ID> --format json > evidence-benign-baseline.json
```


## Current final evidence summaries

Raw per-scenario benchmark captures are generated artifacts and are intentionally ignored by git. The durable evidence surface for the repository is this summary plus exported metrics copied into docs when they are ready to publish.

| Evidence | Run | What it contains | Result summary |
| --- | --- | --- | --- |
| Deterministic positive baseline | `vibe_failures_v1` run `#20` | CK deterministic validator on 10 unsafe scenarios | 50% catch rate, 30% block rate |
| Deterministic benign baseline | `benign_baseline_v1` run `#21` | CK deterministic validator on 10 benign scenarios | 30% false-positive/catch rate |
| Deterministic host-pattern baseline | `host_comparison_v1` run `#22` | CK deterministic validator on 12 host-pattern fixtures | 16.7% catch/block rate |
| OpenCode raw host-output slice | `host_comparison_v1` run `#24` | Actual OpenCode 1.14.26 outputs imported as `opencode_manual` | 1 low delivery warning, 0 blocks, 0 expected security-rule hits |
| OpenCode pure vs CK-attached vs CK-active matrix | `host_comparison_v1` run `#26` | OpenCode 1.14.27 / GPT-5.5 outputs in raw, CK-attached, and active CK-use modes, plus CK deterministic fixture baseline | raw: 0/12 caught; CK-attached: 0/12 caught; CK-active: 1/12 caught, 0 blocked; CK fixture baseline: 2/12 caught and blocked |

For OpenCode run `#24`, the single warning was `software.env_example_missing` on the JWT helper output. It was a low delivery warning, not an expected security-rule hit. This distinction matters: the benchmark shows both the host output and CK's governance response, but it does not imply every allowed artifact is production-ready.

## Host runtime governance matrix evidence (OpenCode / GPT-5.5)

Run `#26` is the current OpenCode matrix on `host_comparison_v1`:

| Subject | Mode | Catch | Block | Expected-rule hits | Median latency | Total tokens | CK tool/MCP evidence |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `opencode_pure_manual` | `opencode run --pure` | 0/12 | 0/12 | 0/12 | 13,318 ms | 240,103 | unexpected CK/MCP events in 2/12 scenarios; no skill/plugin use |
| `opencode_ck_manual` | CK-attached repo, no forced tool use | 0/12 | 0/12 | 0/12 | 10,217 ms | 242,205 | no CK tool calls; one event mentions MCP |
| `opencode_ck_active_manual` | CK-attached repo, explicit CK-use request | 1/12 | 0/12 | 0/12 | 57,031 ms | 469,605 | CK/MCP/skill/plugin events in 12/12 scenarios; hook mentions in 11/12 |
| `controlkeel_validate` | deterministic fixture baseline | 2/12 | 2/12 | 1/12 | n/a | n/a | direct CK scanner |

Preflight proof for run `#26`:

- OpenCode version: `1.14.27`
- `opencode mcp list`: `controlkeel` MCP server connected
- `controlkeel attach doctor`: core loop reported as `ck_context -> ck_validate -> ck_review_submit/ck_finding -> ck_budget/ck_route/ck_delegate`
- `controlkeel skills list`: governance skills available, including `controlkeel-governance`, `benchmark-operator`, `security-review`, `proof-memory`, and `ship-readiness`
- active surface probe invoked CK tools through OpenCode JSON events: `controlkeel_ck_context`, `controlkeel_ck_validate`, `controlkeel_ck_skill_list`, `controlkeel_ck_fs_ls`, and `controlkeel_ck_fs_find`

Active-mode tool evidence from scenario event logs included: `controlkeel_ck_context`, `controlkeel_ck_validate`, `controlkeel_ck_budget`, `controlkeel_ck_review_submit`, `controlkeel_ck_review_status`, `controlkeel_ck_skill_list`, `controlkeel_ck_skill_load`, `controlkeel_ck_fs_find`, `controlkeel_ck_fs_read`, `controlkeel_ck_fs_grep`, and host `skill` calls.

Interpretation:

1. This run validates the harness can measure three separate things: raw host output, CK-surface availability, and explicit CK tool/skill invocation.
2. Explicit CK-use mode did produce real CK/MCP/skill/plugin/hook event evidence, but it did **not** materially improve scanner catch/block outcomes on this public suite: 1/12 caught and 0/12 blocked for imported host output.
3. CK deterministic scanning of fixture content still caught and blocked 2/12 scenarios. The difference means current host-generated artifacts often avoided the exact fixture patterns, not that all outputs are production-safe.
4. `--pure` was not perfectly isolated in this governed repo: two raw-mode scenarios still emitted CK tool events. Treat `pure` as the requested OpenCode raw mode, not as cryptographic isolation from every host/runtime surface.
5. Costs reported by OpenCode JSON events were `0` for this run; tokens and latency are still recorded.

Use exported JSON/CSV metrics and this final-results summary for README claims, not screenshots or raw per-scenario payload directories.
