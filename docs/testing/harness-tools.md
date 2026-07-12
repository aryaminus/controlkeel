# Harness evidence tools

These repository-local tools produce review evidence without updating baselines, invoking models, or contacting external services. Generated inventories and performance reports are artifacts, not authoritative source files.

## Performance regression

`scripts/performance_evidence.py compare` requires at least five samples, matching environment fingerprints, commit-linked candidate evidence, and an explicit tolerated regression. A regression over the threshold exits with status 2 unless `regression_review.status` is `approved`; the tool never updates the baseline.

## Test inventory

`scripts/test_inventory.py generate` scans `test/**/*_test.exs` and writes deterministic JSON when `SOURCE_DATE_EPOCH` is pinned. Optional `# ck:test category=... invariant=... relates=Module.One,Module.Two` metadata records ownership without a duplicate Markdown catalog. `audit` detects stale commits, missing or newly untracked test files, and absent execution evidence.

`scripts/evidence_audit.py` scans an artifact directory for generated test inventories and performance candidates, then rejects stale commits, missing tests, absent execution evidence, and insufficient performance samples. Unknown JSON artifacts are ignored rather than guessed at.

## BEAM profiling

`scripts/profile_beam.py` supports `cprof`, `eprof`, and `fprof`, defaults to a JSON dry-run plan, and requires `--execute` to run. Execution is capped at five minutes and one megabyte of captured output. Use a narrow expression on a quiet machine and attach the JSON result to before/after evidence. Database query plans and telemetry captures remain application-specific and must redact sensitive values.

Visual regression remains separately gated because it requires browser dependencies, CI artifact ownership, and human baseline approval.
