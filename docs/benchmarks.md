# ControlKeel Benchmarks

ControlKeel ships a persisted benchmark engine for comparing governed subjects and external agents against the same scenario suites.

CK’s benchmark model is meant to support the same harness-improvement loop people now use for agent evals:

- mine production traces and failure clusters for candidate evals
- curate small, behavior-rich suites instead of blindly growing noisy corpora
- keep explicit split boundaries so optimization work does not quietly overfit
- use benchmark exports as the durable evidence surface for harness changes

That also makes it the right outer loop for GEPA-style optimization work:

- use CK scenarios and split discipline as the scored signal
- let GEPA-style search mutate prompts, text configs, or harness instructions outside CK
- bring the candidate back through CK benchmark and policy-training surfaces
- promote only when the candidate improves held-out evidence, not just the visible optimization split

## External signal: GEPA holdout transfer (single external study)

An external write-up by Tim Waldin (Apr 2026) reported that GEPA-driven prompt evolution improved a Claude Haiku bug-fix benchmark from **0.6496 to 0.8462 on an unseen holdout** (**+0.1966**, 9 unseen bugs, 3 samples per prompt), with no train/holdout overlap in that setup. Source: Tim Waldin, "Using GEPA to hone Claude Haiku on GitHub bug fixes (+20% solve on untrained bugs)" (tim.waldin.net, 2026-04-19).

Treat this as one external data point, not a universal performance claim. The transferable lesson for CK is benchmark hygiene and promotion discipline:

- preserve strict optimization vs held-out split boundaries
- require explicit overlap checks between training/optimization and holdout scenarios
- use multi-sample evaluation before promotion (for example, multiple seeds/samples per candidate)
- prefer diverse training coverage; tiny narrow sets can overfit and regress on unseen cases
- promote only when held-out evidence improves without safety/regression backslide

## External optimizer interoperability (hone-style pattern)

The `twaldin/hone` project adds a useful interoperability pattern for CK benchmark operators: keep optimization outside the governed scorer, but preserve enough run context for reproducibility and promotion decisions.

Recommended practice when importing external optimizer runs:

- keep one stable scalar score channel (for ranking) and one structured trace channel (for diagnosis)
- capture scorer contract details in metadata (for example: `score_source`, `trace_format`, `trace_count`)
- record optimizer context in metadata (for example: `optimizer_framework`, `mutator`, `target_scope`, `scheduler_strategy`, `observer_mode`)
- if observer/context-updating loops are used, require a rollback guard in promotion notes (for example, revert observer updates when rolling quality drops)
- promote only when held-out evidence improves across multiple samples and safety/regression expectations still pass

This is aligned with CK’s evidence-first posture: external optimizers can search freely, but CK remains the promotion gate and audit trail.

## Blessed external comparison

The recommended first external comparison path is:

- `ControlKeel Validate` vs `OpenCode Manual Import`

This keeps the benchmark reproducible without requiring a deep native integration first.

## Subject types

- `controlkeel_validate` — direct ControlKeel validation path
- `controlkeel_proxy` — ControlKeel governed proxy path
- `manual_import` — placeholder run first, then import captured external output
- `shell` — scriptable subject that writes stdout or files for rescoring

## Split and tag discipline

Benchmark scenarios already carry split-aware metadata:

- `public` for normal reusable suites
- `held_out` for reserved evaluation sets such as `policy_holdout_v1`

Each scenario also carries structured metadata that acts like behavior tags, including fields such as:

- `domain_pack`
- `task_type`
- `artifact_type`
- `security_workflow_phase`
- `memory_sharing_strategy`
- `compaction_strategy`
- any explicit `behavior_tags`

ControlKeel now exposes split summaries and behavior-tag summaries in benchmark run metadata and exports so teams can see whether a result came from optimization-friendly coverage, held-out evidence, or both.

Benchmark run exports also include a `promotion_integrity` profile and `diagnostic_findings` payloads. These are CK-style finding maps, but they are not auto-persisted by the benchmark runner. Operators or background jobs can choose to persist them when a promotion workflow wants durable findings for missing held-out evidence, low behavior diversity, or missing classification evidence.

The intended operating model is:

1. turn recurring production failures into trace packets and failure clusters
2. promote the best candidates into curated benchmark scenarios
3. keep optimization and held-out cases separate
4. compare harness changes against both outcome quality and regression protection

This is the benchmark-side equivalent of treating evals like training data for harness engineering without letting the harness overfit the visible cases.

For multi-agent memory experiments, use metadata to describe the strategy honestly rather than claiming native support CK does not implement itself. Examples:

- `memory_sharing_strategy: "summary"`
- `memory_sharing_strategy: "rag_retrieval"`
- `memory_sharing_strategy: "full_pass_through"`
- `memory_sharing_strategy: "latent_briefing"`
- `memory_sharing_strategy: "late_interaction"`
- `memory_sharing_strategy: "multi_vector_maxsim"`
- `memory_sharing_strategy: "hybrid_late_interaction"`
- `compaction_strategy: "llm_summary"`
- `compaction_strategy: "attention_guided_kv_compaction"`

That lets CK compare governed runs across the same suite while keeping the benchmark evidence clear about what was actually used.

### Retrieval strategy metadata

When benchmarking retrieval quality over CK memory, tag the retrieval backend:

- `retrieval_strategy: "single_vector"` — current pgvector cosine similarity (default)
- `retrieval_strategy: "bm25"` — keyword/lexical baseline
- `retrieval_strategy: "hybrid_bm25_vector"` — combined lexical + dense
- `retrieval_strategy: "late_interaction"` — multi-vector late interaction (ColBERT-style MaxSim or similar)
- `retrieval_strategy: "cross_encoder_rerank"` — retrieve then rerank with a cross-encoder
- `retrieval_strategy: "late_interaction_rerank"` — retrieve then rerank with late interaction scoring

This vocabulary exists so future retrieval experiments can be compared fairly. See `docs/idea/2026-late-interaction-retrieval-research.md` for the research motivating multi-vector and late-interaction approaches.

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

When using benchmarks to improve a harness, prefer:

- small hand-curated suites with strong tags over large noisy dumps
- explicit holdout suites for promotion decisions
- trace-derived eval candidates when failures recur across real sessions
- regression-safe promotion, not score chasing on one visible split

For GEPA-style text optimization specifically:

- treat prompts, system instructions, and lightweight text configs as candidate artifacts
- keep the optimizer outside the governed scoring surface
- enforce zero overlap between optimization/training cases and held-out promotion cases
- run multi-sample candidate evaluations (not single-run score snapshots) before promotion
- use CK exports and run metadata as the audit trail for what changed and why it was promoted
- include optimizer-run metadata (for example scheduler/observer/target-scope settings) so later comparisons stay apples-to-apples

Policy-training promotion gates now carry the same integrity stance. A candidate policy artifact must have validation, held-out, and baseline evidence before promotion can succeed, and the gates include diagnostic finding payloads for review surfaces that want to persist the warning.
