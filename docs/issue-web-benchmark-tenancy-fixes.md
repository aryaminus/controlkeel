<!-- Suggested title: security(web): close benchmark tenancy gaps before cloud launch (PR #259 follow-up) -->
<!-- Suggested labels: security, web, cloud-launch-blocker -->
<!-- Suggested base branch: fix/web-offboarding (review of fix/web-offboarding == main) -->
<!-- Companion issue: CLI/API follow-up tracked separately (docs/issue-cli-api-benchmark-tenancy-followup.md) -->

# security(web): close benchmark tenancy gaps before cloud launch (PR #259 follow-up)

## Context

PR #259 (`security/benchmark-tenancy`, merge `37c9a840`) added a `workspace_id` discriminator to `benchmark_suites` and `benchmark_runs` with the model:

- NULL `workspace_id` = platform content (built-in suites), visible to every tenant
- Non-NULL = tenant data, scoped to the owning workspace
- Empty accessible-set → no rows (fail-closed, matches `Cloud.Scope`)

The core scoping in `lib/controlkeel/benchmark.ex` is correct. The review found the model is **incompletely enforced**: two web-reachable creation paths and one defensive read bypass it. Full review: `docs/pr-259-benchmark-tenancy-review.md`.

Scope of this issue: web surfaces only (LiveViews + context functions reachable from web). CLI/API/protocol surfaces are deliberately out of scope here — cloud/web remain independent; those are tracked in the companion follow-up issue.

## Tasks

### A1 — Observability suite materialization ignores benchmark tenancy (cross-tenant leak)

Evidence:

- `lib/controlkeel/observability.ex:2299` — `ensure_observability_suite/1` creates suites with no `workspace_id` and resolves them with unscoped `Repo.get_by(Suite, slug: slug)` (`:2302`)
- Reachable from the web: `ObservabilityBenchmarkLive.handle_event("approve-draft")` → `Observability.materialize_benchmark_drafts(socket.assigns.opts)` (the LiveView already passes `workspace_id:` in opts, but the materialization path drops it)

Expected: a tenant-approved draft produces a suite owned by that tenant's workspace.
Actual: in cloud mode the suite is created with NULL `workspace_id` and is classified as platform content, so (1) it appears in every other tenant's suite list, and (2) because `benchmark_suites.slug` is globally unique, a second tenant approving a draft with the same `suite_slug` silently resolves to the first tenant's suite and attaches its scenarios to it.

Fix: pass the caller's `workspace_id` from `materialize_benchmark_drafts/1` opts into `ensure_observability_suite/1`; stamp it on the created suite; resolve by `slug + workspace_id` instead of slug alone. Local mode is unaffected — the URL workspace is resolved the same way there.

### A2 — Web run path doesn't verify the resolved suite is platform-or-own

Evidence:

- `lib/controlkeel/benchmark.ex:183` `run_suite/2` resolves the suite via `get_suite_by_slug/1` (`:123`), which is unscoped
- `lib/controlkeel_web/live/benchmarks_live.ex:62` `handle_event("run")` passes form params straight through (workspace stamping applies to the run, not the suite resolution)

Expected: `run_suite` refuses suites that are neither platform (NULL `workspace_id`) nor owned by the caller's workspace.
Actual: once tenant suites exist (via A1 or any future creation path), a crafted `run` event can execute another tenant's suite by slug — spending the caller's money and copying foreign scenario content into a run stamped with the caller's workspace.

Fix: thread the caller's workspace id (or `workspace_ids`) into `run_suite` and reject ineligible suites with `{:error, :suite_not_found}` so existence is not leaked. Local mode keeps unscoped behavior.

### A3 — `fetch_run` defensive fallback is an unscoped read

Evidence: `lib/controlkeel_web/live/benchmarks_live.ex:1067` — when `socket.assigns[:workspace]` is missing, `fetch_run/2` calls unscoped `Benchmark.get_run(id)` (`:1076`).

Expected: cloud mode fails closed (precedent: `observability.ex` `unfiltered/1` at `:1632`, `Cloud.Scope.scope_workspaces/2` empty-list semantics).
Actual: the fallback returns any run by id. Currently unreachable (the show route resolves the workspace via `WorkspaceScope.refresh` first), but it is the exact IDOR shape this PR exists to close, one refactor away from going live.

Fix: branch on `ControlKeel.Runtime.Mode.current()` — local keeps `Benchmark.get_run/1`, cloud returns no rows.

### A4 — UI no longer tells the truth about what's listed

Evidence:

- `lib/controlkeel_web/live/benchmarks_live.ex:~900` — the section is titled "Built-in suites" but `@suites` is now platform suites **plus** the workspace's own suites (after A1, tenant suites)
- `:775` — stat card `@summary.total_suites` counts only builtins (`builtin_suite_count`), while the grid can show more rows

Expected: labels and counts describe the rendered content; suite provenance is visible.
Actual: heading and stat under-report/mislabel for any workspace with custom suites; pre-A1, foreign tenants' suites render here looking like first-party content with no badge.

Fix: rename the section ("Suites"), add a "Built-in" / "Workspace" provenance badge driven by `is_nil(workspace_id)` (follow `docs/ui-style-guide.md` tone tokens), and align `total_suites` with the scoped list or relabel the stat ("Built-in suites").

### A5 — `scope_runs` re-implements `Cloud.Scope.scope_workspaces/2`

Evidence: `lib/controlkeel/benchmark.ex:69-78` duplicates `lib/controlkeel/cloud/scope.ex:54-59` semantics-for-semantics, including the empty-list fail-closed branch. `Cloud.Scope` is the documented policy module for tenant-scoped queries.

Fix: delegate `scope_runs/2` to `Cloud.Scope.scope_workspaces/2`. Keep `scope_suites/2` (`:59`) local — its NULL-or-in semantics intentionally deviate (platform-NULL visibility) — with a comment saying so.

### A6 — No `assoc_constraint(:workspace)` on Run/Suite changesets

Evidence: `lib/controlkeel/benchmark/run.ex` and `lib/controlkeel/benchmark/suite.ex` cast `:workspace_id` but never add `assoc_constraint(:workspace)`.

Expected: an unknown `workspace_id` produces a changeset error.
Actual: it fails at the DB as a raw FK error. Low impact today (the web path stamps a server-resolved workspace), but the schemas now carry a tenant FK and should follow the standard constraint pair.

Fix: add `assoc_constraint(:workspace)` to both changesets; add a test exercising the invalid-id path.

### A7 — Test quality in `tenant_isolation_test.exs`

Evidence:

- `test/controlkeel/benchmark/tenant_isolation_test.exs:17` — `Application.put_env(:controlkeel, :runtime_mode, :cloud)` is never consulted by the code under test (scoping is opt-driven via `workspace_ids:`); it is node-wide global state that concurrent `async: true` tests calling `Mode.current()` also read
- `:133` — `assert is_list(slugs)` would pass even if platform suites were accidentally hidden

Fix: drop the env mutation; assert a builtin slug (e.g. `"vibe_failures_v1"`) is present in the no-workspace case; add the mirror assertion that **runs** are invisible with an empty set even when they belong to a platform suite; add a `run_suite` guard test once A2 lands.

### A8 — Migration file missing trailing newline

Evidence: `priv/repo/migrations/20261012152141_add_workspace_to_benchmarks.exs` has no trailing newline.

Fix: add it.

## Acceptance criteria

- [ ] A1: tenant-materialized suites carry the approving workspace's `workspace_id`; a second tenant with the same draft `suite_slug` gets its own suite; `list_suites`/run form no longer show other tenants' suites in cloud mode
- [ ] A2: `run_suite` with a foreign tenant's suite slug returns `{:error, :suite_not_found}` in cloud mode; platform suites remain runnable everywhere
- [ ] A3: `fetch_run/2` in cloud mode never performs an unscoped read
- [ ] A4: section label, provenance badges, and the `total_suites` stat agree with rendered content
- [ ] A5–A8: applied
- [ ] Local mode: single-workspace behavior unchanged; multi-workspace local users see suites only on their owning workspace (consistent with the URL-scoped direction PR #319 took for runs)
- [ ] `mix precommit` passes; tenant isolation tests extended per A7

## Mode impact

- Cloud: closes cross-tenant visibility and execution gaps (A1, A2), hardens reads (A3), truthful UI (A4)
- Local: no change for single-workspace users; multi-workspace users see suites scoped to the owning workspace, matching how runs already behave
