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
| OpenCode pure vs CK-attached vs CK-active matrix | `host_comparison_v1` run `#29` | OpenCode 1.14.28 using `openai/gpt-5.5`, raw/CK-attached/CK-active modes plus CK deterministic fixture baseline | raw: 1/12 caught; CK-attached: 4/12 caught, 3 blocked; CK-active: 2/12 caught, 0 blocked; CK fixture baseline: 8/12 caught, 7 blocked |
| OpenCode post-scanner-rule rerun | `host_comparison_v1` run `#30` | OpenCode 1.14.28 using `openai/gpt-5.5` after targeted rules for mass assignment, missing rate limit, sensitive request logging, and IDOR | partial/incomplete: CK deterministic baseline 12/12 caught, 9/12 blocked; raw 2/12 caught, 1 blocked; CK-attached 2/12 caught, 1 blocked; CK-active 8/12 completed and 4 scenarios timed out |
| OpenCode isolated raw check | `host_comparison_v1` run `#27` | OpenCode `--pure` in generated isolated workdir | partial 11/12 completed; 2/11 caught, 1/11 blocked; CK/MCP events still leaked in 4/11, so clean no-CK baseline remains unresolved |

For OpenCode run `#24`, the single warning was `software.env_example_missing` on the JWT helper output. It was a low delivery warning, not an expected security-rule hit. This distinction matters: the benchmark shows both the host output and CK's governance response, but it does not imply every allowed artifact is production-ready.

## Host runtime governance matrix evidence (OpenCode / GPT-5.5)

Run `#29` is the current OpenCode matrix on `host_comparison_v1` using model `openai/gpt-5.5`:

| Subject | Mode | Catch | Block | Expected-rule hits | Median latency | Total tokens | CK tool/MCP evidence |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `opencode_pure_manual` | `opencode run --pure` in isolated generated workdir | 1/12 | 0/12 | 0/12 | 17,050 ms | 290,327 | CK/MCP events in 6/12; not a clean no-CK baseline |
| `opencode_ck_manual` | CK-attached repo, no forced tool use | 4/12 | 3/12 | 1/12 | 10,818 ms | 254,581 | CK/MCP events in 1/12 |
| `opencode_ck_active_manual` | CK-attached repo, explicit CK-use request | 2/12 | 0/12 | 0/12 | 47,560 ms | 510,280 | CK/MCP/skill/plugin/hook events in 12/12 |
| `controlkeel_validate` | deterministic fixture baseline | 8/12 | 7/12 | 5/12 | n/a | n/a | direct CK scanner |

Run `#30` post-scanner-rule rerun is recorded as partial evidence, not the current complete host matrix, because `opencode_ck_active_manual` timed out on 4 scenarios even with a 480s per-scenario timeout. It did confirm the targeted deterministic scanner improvements:

| Subject | Mode | Catch | Block | Expected-rule hits | Median latency | Total tokens | CK tool/MCP evidence |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `opencode_pure_manual` | `opencode run --pure` in isolated generated workdir | 2/12 | 1/12 | 1/12 | 16,592 ms | 245,796 | CK/MCP events in 6/12; not a clean no-CK baseline |
| `opencode_ck_manual` | CK-attached repo, no forced tool use | 2/12 | 1/12 | 0/12 | 9,880 ms | 242,555 | no CK/MCP events observed in imported JSON events |
| `opencode_ck_active_manual` | CK-attached repo, explicit CK-use request | 2/8 completed | 0/8 completed | 0/8 completed | 46,675 ms | 334,378 | CK/MCP/skill/plugin events in 8/8 completed; 4/12 scenarios timed out |
| `controlkeel_validate` | deterministic fixture baseline after targeted scanner rules | 12/12 | 9/12 | 9/12 | n/a | n/a | direct CK scanner |

Preflight/host proof for current OpenCode runs:

- OpenCode version: `1.14.28` for run `#29`
- `opencode mcp list`: `controlkeel` MCP server connected
- `controlkeel attach doctor`: core loop reported as `ck_context -> ck_validate -> ck_review_submit/ck_finding -> ck_budget/ck_route/ck_delegate`
- `controlkeel skills list`: governance skills available, including `controlkeel-governance`, `benchmark-operator`, `security-review`, `proof-memory`, and `ship-readiness`
- active surface probe invoked CK tools through OpenCode JSON events: `controlkeel_ck_context`, `controlkeel_ck_validate`, `controlkeel_ck_skill_list`, `controlkeel_ck_fs_ls`, and `controlkeel_ck_fs_find`

Active-mode tool evidence from scenario event logs included CK tools plus host skill calls: `controlkeel_ck_context`, `controlkeel_ck_validate`, `controlkeel_ck_budget`, `controlkeel_ck_review_submit`, `controlkeel_ck_review_status`, `controlkeel_ck_skill_list`, `controlkeel_ck_skill_load`, `controlkeel_ck_fs_find`, `controlkeel_ck_fs_read`, `controlkeel_ck_fs_grep`, and host `skill` calls.

Interpretation:

1. Run `#29` materially improved over run `#26`: CK deterministic baseline moved from 2/12 to 8/12 caught, CK-attached host output moved from 0/12 to 4/12 caught, and CK-active moved from 1/12 to 2/12 caught.
2. The best catch/block score is still the deterministic scanner (`controlkeel_validate`): 8/12 caught and 7/12 blocked in complete run #29, and 12/12 caught with 9/12 blocked in partial post-rule run #30.
3. CK-attached-but-not-forced produced the best imported-host catch/block score in complete run #29: 4/12 caught and 3/12 blocked. Run #30 did not improve imported-host results and remains incomplete because active mode timed out on 4 scenarios.
4. CK-active invoked CK/MCP/skill/plugin/hook surfaces in 12/12 scenarios, but it did not maximize scanner catches. Tool invocation, enforcement, and generated-artifact safety remain separate metrics.
5. `--pure` still leaked CK/MCP events (6/12 in run #29), likely from global OpenCode MCP configuration. Treat raw OpenCode rows as contaminated until a provider-auth-preserving, CK-free config path is available.
6. 0 findings on imported host output does not prove safety. A separate host-output classifier should score unsafe emission, safe remediation, refusal, and CK-enforced blocking.
7. Run #29 remains a public-suite benchmark, not a universal host ranking; use held-out/FPR evidence before promotion claims.
8. Costs reported by OpenCode JSON events were `0`; tokens and latency are recorded.

Use exported JSON/CSV metrics and this final-results summary for README claims, not screenshots or raw per-scenario payload directories.
