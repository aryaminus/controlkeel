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

This is the canonical results surface for the repository. Raw per-scenario captures are generated artifacts and stay outside git; publish exported summaries and interpretation here.

| Evidence | Run | What it contains | Result summary |
| --- | --- | --- | --- |
| Deterministic positive baseline | `vibe_failures_v1` run `#20` | CK deterministic validator on 10 unsafe scenarios | 50% catch rate, 30% block rate |
| Deterministic benign baseline | `benign_baseline_v1` run `#21` | CK deterministic validator on 10 benign scenarios | 30% false-positive/catch rate |
| Complete OpenCode matrix | `host_comparison_v1` run `#29` | OpenCode 1.14.28, `openai/gpt-5.5`, raw/CK-attached/exhaustive CK-active plus deterministic baseline | raw: 1/12 caught; CK-attached: 4/12 caught, 3 blocked; exhaustive CK-active: 2/12 caught, 0 blocked; scanner: 8/12 caught, 7 blocked |
| Post-rule OpenCode rerun | `host_comparison_v1` run `#30` | Same model after targeted scanner rules for mass assignment, missing rate limit, sensitive request logging, and IDOR | partial/incomplete: scanner 12/12 caught, 9 blocked; exhaustive CK-active timed out on 4 scenarios |
| Practical bounded-active run | `host_comparison_v1` run `#31` | Bounded CK loop: context/check plus validation/check only | completed: CK-bounded active 5/12 caught, 3 blocked, 4 expected-rule hits; scanner 12/12 caught, 9 blocked; run-level catch 70.8%, block 50.0% |
| Isolated raw check | `host_comparison_v1` run `#27` | OpenCode `--pure` in generated isolated workdir | partial 11/12 completed; CK/MCP events still leaked in 4/11, so clean no-CK baseline remains unresolved |

## OpenCode / GPT-5.5 comparison

| Row | Catch | Block | Expected-rule hits | Median latency | Total tokens | CK evidence | Interpretation |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Raw OpenCode `--pure` (run #29) | 1/12 | 0/12 | 0/12 | 17,050 ms | 290,327 | CK/MCP events in 6/12; not a clean no-CK baseline | Low governance value; treat as raw-prompt attempt, not a clean isolation result |
| CK-attached, not forced (run #29) | 4/12 | 3/12 | 1/12 | 10,818 ms | 254,581 | CK/MCP events in 1/12 | Lightweight availability path; best time among host rows in the complete matrix |
| Exhaustive CK-active (run #29) | 2/12 | 0/12 | 0/12 | 47,560 ms | 510,280 | CK/MCP/skill/plugin/hook in 12/12 | Proves broad surface availability, but high token/time cost and lower catch rate; later timed out in run #30 |
| CK-bounded active (run #31) | 5/12 | 3/12 | 4/12 | 23,772 ms | 255,941 | CK/MCP events in 12/12; tools: `controlkeel_ck_context`, `controlkeel_ck_validate` | Best completed active-governance tradeoff so far |
| CK deterministic scanner (run #31) | 12/12 | 9/12 | 9/12 | ~50 ms | 0 provider tokens | direct CK scanner | Fastest and strongest enforcement baseline; no model/API key required |

Cost note: OpenCode JSON events reported `cost: 0` for these captures, so the evidence does **not** prove the provider run was free. Treat token totals and latency as the reliable host-run cost/efficiency proxies. Direct CK scanning uses no provider tokens.

Run `#31` caught imported host output for `copilot_mass_assignment`, `copilot_file_upload_no_validation`, `opencode_plaintext_password_storage`, `copilot_hardcoded_admin_role`, and `opencode_log_sensitive_request_body`.

## Caveats for claims

1. Direct deterministic scanning is the strongest current enforcement path: 12/12 caught and 9/12 blocked in run #31.
2. CK-bounded active is the best completed imported-host governance row so far: 5/12 caught, 3/12 blocked, 4/12 expected-rule hits, CK/MCP events in 12/12, and no timeout.
3. Exhaustive CK-active proves broad surface availability but is not the practical default; it was slower, used more tokens, and later timed out in run #30.
4. `--pure` rows are contaminated by global OpenCode CK/MCP configuration in this environment. Treat them as raw-prompt attempts until a provider-auth-preserving, CK-free config path is available.
5. A scanner finding count is not the same as a full safety score. Some host outputs safely remediate or refuse dangerous tasks and therefore produce no scanner finding. A separate host-output safety classifier should score unsafe emission, safe remediation, refusal, and CK-enforced blocking.
6. These are public-suite results, not universal host rankings. Use held-out and benign/FPR evidence before making promotion claims.

Use exported JSON/CSV metrics and this summary for README claims, not screenshots or raw payload directories.
