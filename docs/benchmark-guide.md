# Multi-Host Benchmark Guide

This guide explains how to use ControlKeel's benchmark engine to compare governance outcomes across coding agents — Copilot, OpenCode, Gemini, Codex, Claude, and others — and show users how much ControlKeel improves security posture.

## Quick start: Copilot vs OpenCode

### Step 1: Configure subjects

Copy the multi-host subject template into your governed project:

```bash
cp docs/examples/multi-host-benchmark-subjects.json controlkeel/benchmark_subjects.json
```

Or use the existing project config that already includes Copilot and OpenCode:

```bash
# Already done if you're in the ControlKeel repo:
cat controlkeel/benchmark_subjects.json
```

### Step 2: Run the cross-host comparison

```bash
controlkeel benchmark run \
  --suite host_comparison_v1 \
  --subjects controlkeel_validate,opencode_manual,copilot_manual \
  --baseline-subject controlkeel_validate
```

The `opencode_manual` and `copilot_manual` results will enter `awaiting_import` state.

### Step 3: Import external host output

Capture what Copilot or OpenCode actually produces for each scenario prompt, then import it:

```bash
controlkeel benchmark import <RUN_ID> copilot_manual payload.json
```

Where `payload.json` looks like:

```json
{
  "scenario_slug": "copilot_inline_stripe_key",
  "content": "STRIPE_SECRET_KEY = \"sk_live_...\"\n...",
  "path": "config/payments.py",
  "kind": "code",
  "duration_ms": 2400,
  "metadata": {
    "agent": "copilot",
    "capture": "manual",
    "model": "gpt-4.1"
  }
}
```

### Step 4: Compare results

```bash
controlkeel benchmark show <RUN_ID>
```

Or open `/benchmarks/runs/<RUN_ID>` in the web UI for the full matrix view with OWASP classification metrics.

## Built-in comparison suite: host_comparison_v1

The `host_comparison_v1` suite contains 12 scenarios specifically designed to measure how often coding agents produce unsafe output that ControlKeel catches. Each scenario includes:

- **A realistic prompt** — what you'd actually ask an agent to do
- **Unsafe content** — representative output that unguarded agents commonly produce
- **Expected rules** — which CK rules should fire
- **Expected decision** — whether CK should block or warn
- **Host pattern tags** — `copilot`, `opencode`, or `both` indicating which hosts commonly produce this pattern

### Scenario coverage

| # | Scenario | Category | Host pattern | Risk |
|---|----------|----------|-------------|------|
| 1 | Inline Stripe secret | security | copilot | critical |
| 2 | JWT with none algorithm | security | opencode | critical |
| 3 | CORS wildcard + credentials | security | both | high |
| 4 | Mass assignment in Ecto cast | security | copilot | critical |
| 5 | Raw SQL in Phoenix controller | security | opencode | critical |
| 6 | Debug endpoint leaking env vars | security | both | critical |
| 7 | File upload without validation | security | copilot | high |
| 8 | Plaintext password storage | security | opencode | critical |
| 9 | API with no rate limiting | security | both | high |
| 10 | Hardcoded admin role check | security | copilot | critical |
| 11 | Logging full request body + PII | privacy | opencode | high |
| 12 | IDOR in API show endpoint | security | both | critical |

## Adding new hosts

Adding Gemini, Codex, Claude, or any future host requires **one entry** in `controlkeel/benchmark_subjects.json`:

```json
{
  "id": "gemini_manual",
  "label": "Gemini CLI (Manual Import)",
  "type": "manual_import"
}
```

For automated replay, use the shell wrapper:

```json
{
  "id": "gemini_shell",
  "label": "Gemini CLI (Shell Wrapper)",
  "type": "shell",
  "command": "./scripts/benchmark-host.sh",
  "args": ["gemini"],
  "working_dir": ".",
  "timeout_ms": 120000,
  "output_mode": "stdout"
}
```

The `scripts/benchmark-host.sh` harness includes template routing for `opencode`, `copilot`, `gemini`, `codex`, and `claude`. Verify each CLI's non-interactive invocation in your environment before treating shell-subject results as production evidence.

## Interpreting results

### Classification metrics

Every benchmark run computes:

- **TPR (True Positive Rate)**: Of the scenarios that should trigger findings, how many did CK catch?
- **FPR (False Positive Rate)**: Of the benign scenarios, how many did CK incorrectly flag? (Use the `benign_baseline_v1` suite for this.)
- **Youden's J (TPR − FPR)**: Single-number quality metric. Higher is better. 1.0 is perfect.

### Improvement delta

The comparison naturally shows the improvement delta:

- **CK catch rate** vs **unguarded host catch rate** (typically 0% since unguarded hosts have no governance)
- The delta is the number of vulnerabilities CK caught that the host would have shipped

### Separate closed-loop and open-loop runs

If you benchmark overnight or AFK behavior, separate two different questions:

- **Closed-loop**: did the governed run finish a bounded, reviewable slice?
- **Open-loop**: did the governed run make acceptable progress on a named metric or search space?

Do not score those the same way. Closed-loop runs care about completion, reviewability, and regression safety. Open-loop runs care about progress quality, not fake completion theater.

When importing or exporting those runs, use metadata that makes the loop shape explicit:

- `loop_shape: "closed"` or `loop_shape: "open"`
- `progress_contract: "finish_slice"`, `shrink_search_space`, or `improve_metric`
- `handoff_contract: "relay_structured"` when the run uses baton-style planner/worker/validator handoffs

### Add pushback cases, not just exploit cases

If you want benchmark results that feel closer to real expert use, do not limit suites to "does the model emit unsafe code." Add a small number of scenarios where the correct move is to reject or challenge the task framing.

Examples:

- a prompt built on an invalid causal premise where the best answer is "this cannot be inferred"
- a pseudo-analytical request that sounds technical but is actually nonsense
- an underspecified expert task where clarification is better than confident execution

Those scenarios are valuable because many models will still produce polished but wrong output instead of pushing back. In CK terms, that is often a benchmark-design issue rather than a missing scanner rule.

### Run the paired benign suite for FPR

```bash
controlkeel benchmark run \
  --suite benign_baseline_v1 \
  --subjects controlkeel_validate \
  --baseline-subject controlkeel_validate
```

This measures false positive rate — CK should allow all 10 benign patterns.

## Recommended comparison workflow

1. Run `host_comparison_v1` with `controlkeel_validate` only → establishes CK baseline
2. Run `host_comparison_v1` with `controlkeel_validate,opencode_manual,copilot_manual` → creates import slots
3. Import captured host output one scenario at a time for each subject
4. Run `benign_baseline_v1` with `controlkeel_validate` → measures FPR
5. Export both runs as CSV or JSON for your documentation

```bash
controlkeel benchmark export <RUN_ID> --format csv > host_comparison_results.csv
```

## CLI quick reference

```bash
# List all suites and subjects
controlkeel benchmark list

# Run cross-host comparison
controlkeel benchmark run --suite host_comparison_v1 --subjects controlkeel_validate,opencode_manual,copilot_manual

# Import external output
controlkeel benchmark import <RUN_ID> copilot_manual payload.json

# Show results with classification metrics
controlkeel benchmark show <RUN_ID>

# Export for documentation
controlkeel benchmark export <RUN_ID> --format csv
controlkeel benchmark export <RUN_ID> --format json
```
