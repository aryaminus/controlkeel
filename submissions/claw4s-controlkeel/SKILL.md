---
name: controlkeel-claw4s-benchmark
description: Reproduce a ControlKeel calibration benchmark for coding-agent governance on paired public failure and benign suites, then generate a compact markdown summary and a LaTeX-ready table.
allowed-tools: Bash(git *, mix *, mkdir *, sed *, tee *, grep *, tail *, pwd, ls *, cp *)
---

# ControlKeel Claw4S Benchmark

This skill reproduces the benchmark workflow used in the ControlKeel Claw4S submission.

The goal is not to claim that ControlKeel fully solves coding-agent safety. The goal is to run a deterministic, public calibration benchmark that shows what the current built-in validator catches, what it misses, and where it still produces false positives.

## Inputs

- `CONTROLKEEL_REPO_URL` (optional): git URL to clone when you are not already inside the ControlKeel repo.
- `CONTROLKEEL_REPO_DIR` (optional): absolute path where the repo should live when cloning.

Default clone URL:

```bash
https://github.com/aryaminus/controlkeel.git
```

## Prerequisites

- Git
- Erlang/OTP and Elixir compatible with the repository
- Internet access for `mix deps.get`

This workflow does **not** require:

- OpenAI, Anthropic, or other provider API keys
- Node.js or asset compilation
- external coding-agent hosts such as Claude Code, Cursor, or OpenCode

## Outputs

This skill writes all generated artifacts under:

```bash
submissions/claw4s-controlkeel/output
```

Expected files:

- `vibe_failures_v1_run.log`
- `benign_baseline_v1_run.log`
- `vibe_failures_v1_export.log`
- `benign_baseline_v1_export.log`
- `summary.md`
- `metrics.json`
- `results_table.tex`

## Step 1: Enter the repository

If the current directory already looks like the ControlKeel repo, stay there. Otherwise clone it.

```bash
if [ -f mix.exs ] && grep -q 'app: :controlkeel' mix.exs; then
  REPO_ROOT="$PWD"
else
  REPO_ROOT="${CONTROLKEEL_REPO_DIR:-$PWD/controlkeel}"
  if [ ! -d "$REPO_ROOT/.git" ]; then
    git clone "${CONTROLKEEL_REPO_URL:-https://github.com/aryaminus/controlkeel.git}" "$REPO_ROOT"
  fi
fi
cd "$REPO_ROOT"
pwd
```

Expected result:

- The working directory is the ControlKeel repository root.

## Step 2: Install dependencies and bootstrap the project

```bash
mix local.hex --force
mix local.rebar --force
mix deps.get
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
```

Expected result:

- Dependencies install successfully.
- The test SQLite database is created and migrated.
- No web server, provider key, or asset build is required.

## Step 3: Create an output directory

```bash
mkdir -p submissions/claw4s-controlkeel/output
```

Expected result:

- `submissions/claw4s-controlkeel/output` exists.

## Step 4: Run the positive suite

```bash
MIX_ENV=test mix ck.benchmark run \
  --suite vibe_failures_v1 \
  --subjects controlkeel_validate \
  --baseline-subject controlkeel_validate \
  | tee submissions/claw4s-controlkeel/output/vibe_failures_v1_run.log
```

Expected result:

- The log contains a line like `Benchmark run #<ID> completed.`

Extract the run ID:

```bash
VIBE_RUN_ID="$(sed -n 's/.*Benchmark run #\([0-9][0-9]*\) completed\./\1/p' submissions/claw4s-controlkeel/output/vibe_failures_v1_run.log | tail -n 1)"
test -n "$VIBE_RUN_ID"
echo "$VIBE_RUN_ID"
```

## Step 5: Run the benign suite

```bash
MIX_ENV=test mix ck.benchmark run \
  --suite benign_baseline_v1 \
  --subjects controlkeel_validate \
  --baseline-subject controlkeel_validate \
  | tee submissions/claw4s-controlkeel/output/benign_baseline_v1_run.log
```

Expected result:

- The log contains a line like `Benchmark run #<ID> completed.`

Extract the run ID:

```bash
BENIGN_RUN_ID="$(sed -n 's/.*Benchmark run #\([0-9][0-9]*\) completed\./\1/p' submissions/claw4s-controlkeel/output/benign_baseline_v1_run.log | tail -n 1)"
test -n "$BENIGN_RUN_ID"
echo "$BENIGN_RUN_ID"
```

## Step 6: Export both runs as JSON

The benchmark is exported from the `test` environment so the output is clean JSON.

```bash
MIX_ENV=test mix ck.benchmark export "$VIBE_RUN_ID" --format json \
  > submissions/claw4s-controlkeel/output/vibe_failures_v1_export.log

MIX_ENV=test mix ck.benchmark export "$BENIGN_RUN_ID" --format json \
  > submissions/claw4s-controlkeel/output/benign_baseline_v1_export.log
```

Expected result:

- Both export log files exist and end with a valid JSON object.

## Step 7: Analyze the exported results

```bash
mix run submissions/claw4s-controlkeel/scripts/analyze_results.exs \
  submissions/claw4s-controlkeel/output/vibe_failures_v1_export.log \
  submissions/claw4s-controlkeel/output/benign_baseline_v1_export.log \
  submissions/claw4s-controlkeel/output
```

Expected result:

- The script writes `summary.md`, `metrics.json`, and `results_table.tex`.
- The stdout summary reports catch rate, block rate, TPR, FPR, and notable misses / false positives.

## Step 8: Inspect the generated artifacts

```bash
ls -la submissions/claw4s-controlkeel/output
sed -n '1,200p' submissions/claw4s-controlkeel/output/summary.md
```

Expected result:

- A compact, paper-ready result summary is present.
- The LaTeX table can be pasted into the research note directly.

## Interpretation Notes

- `vibe_failures_v1` is the public positive suite: scenarios whose `expected_decision` is `warn` or `block`.
- `benign_baseline_v1` is the paired public negative suite: corrected scenarios whose `expected_decision` is `allow`.
- In the repository's benchmark operator playbook, public suites are designated for comparable external reporting and normal operator use.
- The benchmark uses the built-in `controlkeel_validate` subject, which maps directly to the ControlKeel validation path rather than an external coding-agent host.
- This fixed-subject choice is deliberate: it isolates the governance core from host-specific attach quality and companion-package differences.
- The same benchmark engine also supports `controlkeel_proxy`, `manual_import`, and `shell` subjects when you want external comparisons later.
- This skill is a calibration benchmark for the governance layer. It does not claim universal coverage, autonomous release safety, or superiority over all external systems.
