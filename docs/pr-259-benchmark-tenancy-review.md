# PR #259 Review — `security/benchmark-tenancy` merged into main

Review of merge commit `37c9a840` (PR #259: commits `b356c1e5` + `aaec3fad`), traced through to current main (which includes the later PR #319 workspace-scope restructure), covering both the web and CLI/API surfaces for how the new tenancy model holds up.

**What the PR did well:** the shared-schema + `workspace_id` discriminator model matches the rest of the codebase (sessions, findings), NULL = platform content is a sensible convention, empty-set → no rows matches `Cloud.Scope` semantics, the migration has the right indexes, and the web run path stamps a server-resolved workspace (never form params). The gaps are in coverage: the PR scoped *reads* but left the two web-reachable *creation* paths and one defensive read unguarded.

---

## Part A — Web, features, UI/UX (fix before controlkeel.com launch)

### A1 — HIGH: Observability suite materialization ignores benchmark tenancy (cross-tenant leak)

**Where:** `lib/controlkeel/observability.ex` — `ensure_observability_suite/1`, `materialize_benchmark_draft/1`

**What's wrong:** PR #259 established "NULL workspace_id = platform content visible to every tenant," but the only web-reachable path that creates suites — approving a benchmark draft on the workspace observability page (`ObservabilityBenchmarkLive.handle_event("approve-draft")` → `materialize_benchmark_drafts`) — creates suites with **no workspace_id**. Two consequences in cloud mode:

1. Every tenant's materialized observability suite becomes "platform content" and shows up in **all other tenants'** suite dropdowns and suites tables (`list_suites` includes NULL-workspace rows by design).
2. `Repo.get_by(Suite, slug: slug)` with the globally-unique slug (`observability-<draft.suite_slug>`) means tenant B approving a draft with the same suite slug silently gets **tenant A's suite**, and B's scenarios are attached to it — cross-tenant scenario sharing, plus confusing provenance.

**Why it matters:** this is exactly the leak class PR #259 exists to prevent, and it's reachable by a normal admin action at controlkeel.com on day one.

**Recommendation:** pass the caller's `workspace_id` through `materialize_benchmark_drafts` opts (the LiveView already sends `workspace_id:` in opts) into `ensure_observability_suite`, and resolve the suite by `slug + workspace_id` instead of slug alone. Local mode is unaffected: the workspace is resolved the same way there.

### A2 — HIGH: Web run path doesn't verify the resolved suite is platform-or-own

**Where:** `lib/controlkeel/benchmark.ex` `run_suite/2` → `get_suite_by_slug/1` (unscoped); `benchmarks_live.ex` `handle_event("run")`

**What's wrong:** suites are scoped in listings and run *reads*, but `run_suite` resolves the suite by slug **unscoped**. Once tenant suites exist (via A1, or any future creation path), a crafted `run` event from the Benchmarks page can execute **another tenant's suite by slug** — spending the caller's money and copying the foreign suite's scenario content into a run stamped with the caller's workspace (visible to the caller's whole workspace).

**Why it matters:** tenancy enforced on read but not on the execution entry point defeats the model; the suite selector only shows safe options, but the server must not trust that.

**Recommendation:** inside `run_suite` (or in BenchmarksLive before calling it), accept the caller's `workspace_ids`/URL workspace and reject suites whose `workspace_id` is neither NULL nor in the caller's set (`{:error, :suite_not_found}` is the right response so existence isn't leaked). Local mode passes unscoped as today.

### A3 — MEDIUM: `fetch_run` falls back to an unscoped read

**Where:** `benchmarks_live.ex` lines 1063–1078

**What's wrong:** when `socket.assigns[:workspace]` is missing, `fetch_run` calls unscoped `Benchmark.get_run(id)`. The comment calls it "a defensive fallback for a page without a resolved workspace" — in cloud mode that fallback is the exact IDOR this PR was meant to close, one refactor away from going live. The codebase's own precedent (`observability.ex` `unfiltered/1`, `Cloud.Scope` empty-list semantics) is to **fail closed** in cloud, unscoped only in local.

**Recommendation:** change the fallback to: `Mode.current() == :local → Benchmark.get_run(id)`, otherwise no rows. Currently unreachable (the show route always resolves a workspace via `WorkspaceScope.refresh`), which is precisely why it's a cheap, safe hardening.

### A4 — MEDIUM: UI no longer tells the truth about what's listed

**Where:** `benchmarks_live.ex` heex ~line 900 ("Built-in suites" section), stat card ~line 775

**What's wrong:** after this PR, `@suites` = platform suites **+ the workspace's own suites**, but the section header still says "Built-in suites" and the helper text only describes built-ins. Meanwhile the summary card `total_suites` counts only builtins (`builtin_suite_count`) while the grid can show more rows — the numbers visibly disagree for any workspace with custom suites. In cloud (pre-A1-fix) foreign tenants' suites would also render here looking like first-party content, with no provenance badge.

**Recommendation:** rename the section ("Suites"), add a small "Built-in" / "Workspace" provenance badge driven by `is_nil(workspace_id)`, and either make `total_suites` match the scoped list or relabel the stat ("Built-in suites").

### A5 — LOW: `scope_runs` re-implements `Cloud.Scope.scope_workspaces/2`

**Where:** `benchmark.ex` lines 66–78

**What's wrong:** `Cloud.Scope` is the documented policy ("every cloud-facing Repo query must enforce workspace_id… callers never write an unscoped Repo.get"); `scope_runs/2` duplicates it semantics-for-semantics including the empty-list fail-closed branch. Only `scope_suites` genuinely differs (NULL-or-in).

**Recommendation:** delegate `scope_runs` to `Cloud.Scope.scope_workspaces/2`; keep `scope_suites` local with a comment noting it intentionally deviates (platform-NULL visibility).

### A6 — LOW: No `assoc_constraint(:workspace)` on Run/Suite changesets

**What's wrong:** a nonexistent `workspace_id` fails at the DB as a raw FK error (500-ish behavior) instead of a changeset error. Low impact today because the web path stamps a server-resolved workspace, but the schemas now carry a tenant FK that deserves the standard constraint pair.

**Recommendation:** add `assoc_constraint(:workspace)` (requires the `belongs_to` to also `foreign_key: :workspace_id` explicitly or rely on default — verify with a test) to both changesets.

### A7 — LOW (tests): misleading setup + weak assertions in `tenant_isolation_test.exs`

**What's wrong:**

- The `setup` mutates global `Application.put_env(:controlkeel, :runtime_mode, :cloud)`, but nothing under test reads that key — scoping is purely opt-driven (`workspace_ids:`). It's dead global state; with `async: false` in this module it won't self-flake, but concurrent `async: true` tests that call `Mode.current()` share the node-wide env.
- `"a caller with no workspaces still sees platform suites"` asserts only `is_list(slugs)` — it would pass even if platform suites were accidentally hidden. Assert a builtin slug (e.g. `"vibe_failures_v1"`) is present, and add the mirror assertion that **runs** of a platform suite are still invisible with an empty set.
- `suite(ws)` / `run(suite, ws)` helpers use `ws && ws.id` where `ws` is always a truthy struct — redundant.

**Recommendation:** drop the env mutation, strengthen the assertions, add a `run_suite` guard test once A2 lands.

### A8 — TRIVIAL: migration file missing trailing newline

`priv/repo/migrations/20261012152141_add_workspace_to_benchmarks.exs` — one-byte fix.

---

## Part B — CLI, API, server (follow-up branch; do not block launch on these, but B1 is the first follow-up)

### B1 — HIGH (cloud): `/api/v1/benchmarks*` is fully unscoped

`list_benchmarks`, `create_benchmark_run` (creates NULL-workspace runs tenants can never see), `get_benchmark_run` + `compare_benchmark_run` + `export_benchmark_run` (IDOR across tenants), `import_benchmark_result` (write into any run id). `ApiAuth` authenticates service accounts **in every mode**, so these are live surfaces at controlkeel.com. Scope everything by the authenticated principal's workspace(s) (`CloudWorkspaceKeyAuth`-style), or fail closed per the existing "fail closed on hosted API access" precedent.

### B2 — MEDIUM: CLI benchmark paths undefined in cloud

`cli/dispatch/benchmarks_harness.ex` (unscoped `run_suite`/`get_run`) and `cli/dispatch/observability.ex` → `run_observability_benchmark` (no workspace stamp in attrs). Fine against a local DB; pick an explicit cloud policy (deny vs. scope) so it can't silently write NULL-workspace rows into a shared cloud DB.

### B3 — MEDIUM: `latest_completed_run/2` is a global unscoped lookup

Used by self-harness regression validation (`mission.ex:2289`); in cloud it would adopt some other tenant's run as the baseline for a builtin suite. Local-only today — fail closed in cloud mode when the CLI/cloud story is designed.

### B4 — LOW: unscoped public entry points remain

`Benchmark.get_run/1` and `get_suite_by_slug/1` stay public and unscoped alongside the scoped variants. Audit all callers as part of the B pass.

### B5 — LOW: global unique index on `benchmark_suites.slug`

With tenant suites in cloud, slugs are globally unique — slug squatting across tenants and `get_suite_by_slug` ambiguity. Consider a composite `[:workspace_id, :slug]` unique index (platform rows keep global uniqueness) — schema change, so bundle it with the Part B pass.

---

## Summary — what to fix first

1. **A1** (observability suite tenancy + slug collision) — the only must-fix-before-launch item; it creates cross-tenant-visible data through a normal admin action at controlkeel.com.
2. **A2** (run-path suite guard) — completes the tenancy model the PR started; server-side enforcement where the form can't be trusted.
3. **A3** (fail-closed `fetch_run`) — three-line hardening aligned with existing `Cloud.Scope`/`unfiltered` precedent.
4. **A4** (UI labeling + stat consistency) — small HEEx changes; becomes trivial once A1 lands.

**Optional / polish:** A5–A8 (Cloud.Scope reuse, assoc constraints, test tightening, newline).

**Local-mode impact of the Part A fixes:** none for single-workspace users. Multi-workspace local users will see observability suites only on their owning workspace — consistent with the URL-scoped direction PR #319 already took for runs, and `fetch_run`/listings keep their unscoped behavior in local mode if A3 branches on `Mode.current()`.

**Follow-up branch (Part B):** start with B1 — the API benchmark endpoints are authenticated-but-unscoped and will be a live cross-tenant surface the moment controlkeel.com takes cloud traffic. B5's index change belongs there too since it's a migration.

**Process note for issue creation:** PR #259's `live_auth_test.exs` changes were superseded by the later benchmarks-workspace-scope restructure (the global run page and `member_run` helper are gone from main), so there's nothing left to fix there — the durable review targets are `observability.ex`, `benchmark.ex`, and `benchmarks_live.ex` as listed above.
