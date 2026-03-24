# ControlKeel Benchmarks

ControlKeel ships a persisted benchmark engine for comparing governed subjects and external agents against the same scenario suites.

## Blessed external comparison

The recommended first external comparison path is:

- `ControlKeel Validate` vs `OpenCode Manual Import`

This keeps the benchmark reproducible without requiring a deep native integration first.

## Subject types

- `controlkeel_validate` — direct ControlKeel validation path
- `controlkeel_proxy` — ControlKeel governed proxy path
- `manual_import` — placeholder run first, then import captured external output
- `shell` — scriptable subject that writes stdout or files for rescoring

## Web UI quick presets

On `/benchmarks`, use **Quick presets** (OpenCode comparison, ControlKeel validate only, Validate + governed proxy) to fill the subject and baseline fields, then adjust if needed. The subjects field still accepts a comma-separated list and supports browser autocomplete from **Available subjects**.

## OpenCode benchmark setup

Copy the example subject file into the governed project:

```bash
mkdir -p controlkeel
cp docs/examples/opencode-benchmark-subjects.json controlkeel/benchmark_subjects.json
```

Then run:

```bash
controlkeel benchmark run \
  --suite vibe_failures_v1 \
  --subjects controlkeel_validate,opencode_manual \
  --baseline-subject controlkeel_validate
```

The `opencode_manual` result will enter `awaiting_import` state.

## Import external output

Capture the OpenCode-produced content for the target scenario and write a payload like:

```json
{
  "scenario_slug": "client_side_auth_bypass",
  "content": "document.getElementById('admin-panel').innerHTML = userInput;",
  "path": "assets/js/admin.js",
  "kind": "code",
  "duration_ms": 16,
  "metadata": {
    "agent": "opencode",
    "capture": "manual"
  }
}
```

Import it:

```bash
controlkeel benchmark import <RUN_ID> opencode_manual --file payload.json
```

## Shell wrapper upgrade path

When you already have a scripted OpenCode harness, replace `opencode_manual` with the `opencode_shell` subject from `docs/examples/opencode-benchmark-subjects.json` and point its `command` to your wrapper script.

## Interpretation

Use benchmark results as product evidence, but keep the claim precise:

- ControlKeel ships a blessed OpenCode comparison path
- external subjects can be imported or scripted
- not every external agent is zero-config or bridge-native yet
