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
