<!-- Suggested title: security(cli/api): scope benchmark surfaces for cloud mode (follow-up) -->
<!-- Suggested labels: security, cli, api, follow-up -->
<!-- Companion issue: web fixes tracked in docs/issue-web-benchmark-tenancy-fixes.md (Part A lands first) -->
<!-- Not a cloud-launch blocker: CLI keeps using the local DB; controlkeel.com web surfaces are covered by the companion issue -->

# security(cli/api): scope benchmark surfaces for cloud mode (follow-up)

## Context

PR #259 (`security/benchmark-tenancy`) scoped the web benchmark surfaces to a `workspace_id` discriminator, but the CLI and `/api/v1` benchmark paths still bypass it. Today this is safe because the CLI runs against the local DB and cloud web does not replicate CLI features. It becomes a live cross-tenant surface the moment authenticated API traffic reaches a shared cloud database, so this issue defines the follow-up branch and the policy decisions needed before then.

Full review: `docs/pr-259-benchmark-tenancy-review.md`.

## Tasks

### B1 — `/api/v1/benchmarks*` is fully unscoped (highest priority)

Evidence:

- Router: `lib/controlkeel_web/router.ex:358-363` under `scope "/api/v1"` with `pipe_through :api` (`:304`)
- `ApiAuth` (`lib/controlkeel_web/plugs/api_auth.ex`) authenticates service accounts **in every mode**, so these endpoints serve authenticated callers in cloud deployments too
- `lib/controlkeel_web/controllers/api_controller.ex`:
  - `:520` `list_benchmarks/2` — no `workspace_ids`, unscoped listing
  - `:541` `create_benchmark_run/2` — no workspace stamp; in cloud mode the created run has NULL `workspace_id` and is invisible to every tenant (paid work nobody can see)
  - `:564` `get_benchmark_run/2` — unscoped `Benchmark.get_run/1` → IDOR across tenants
  - `:574` `compare_benchmark_run/2` and `:620` `export_benchmark_run/2` — same unscoped read path
  - `:584` `import_benchmark_result/2` — writes into any run id, regardless of owner

Expected: every endpoint scopes to the authenticated principal's workspace(s), consistent with the existing cloud authn (`CloudWorkspaceKeyAuth`) and the "fail closed on hosted API access" precedent.
Actual: authenticated service accounts can list, read, compare, export, import, and create benchmark data across tenants.

Fix options (decide one):
1. Resolve the principal's workspace from the service account binding and thread `workspace_ids:` / `workspace_id:` into the `Benchmark` calls (reuse the scoped variants added by PR #259).
2. Fail closed: deny benchmark endpoints for non-local callers until scoping exists.

### B2 — CLI benchmark paths are undefined in cloud mode

Evidence:

- `lib/controlkeel/cli/dispatch/benchmarks_harness.ex:180` — `Benchmark.run_suite(attrs, project_root)` with no workspace stamp; `:209` — `Benchmark.get_run(run_id)` unscoped
- `lib/controlkeel/cli/dispatch/observability.ex:334` → `Observability.run_observability_benchmark/2` (`lib/controlkeel/observability.ex:493`) — builds run attrs without `workspace_id`, so runs created against a shared cloud DB would be NULL-workspace rows invisible to tenants

Expected: an explicit policy — either deny benchmark mutation commands in cloud mode (match the hosted-access fail-closed posture) or bind them to a workspace the caller can access.
Actual: behavior against a shared cloud DB is undefined and silently writes tenant-orphaned rows.

Fix: pick and implement the policy; document it in the CLI reference (`docs/cli-reference.md`).

### B3 — `latest_completed_run/2` is a global unscoped lookup

Evidence: `lib/controlkeel/benchmark.ex:168` — finds the most recent completed run for a suite slug + subject across **all** tenants; called from self-harness regression validation at `lib/controlkeel/mission.ex:2289`.

Expected (cloud): a baseline must come from the caller's own tenant, or none.
Actual (cloud): validation could adopt another tenant's run of a platform suite as its regression baseline.

Fix: local-only today; fail closed in cloud mode when the CLI/cloud story lands, or scope by the caller's workspace set.

### B4 — Unscoped public entry points remain next to the scoped variants

Evidence: `Benchmark.get_run/1` (`lib/controlkeel/benchmark.ex:131,138`) and `get_suite_by_slug/1` (`:123`) stay public and unscoped after PR #259 added `get_run_for_user/2` (`:150`).

Fix: audit all callers; either convert remaining tenant-facing callers to the scoped variants or mark the unscoped ones `@doc false`-style internal-only with a comment stating their local-mode-only contract. Note: A2 in the companion web issue already closes the web path through `get_suite_by_slug`.

### B5 — Global unique index on `benchmark_suites.slug`

Evidence: `priv/repo/migrations/20260319023632_create_benchmark_engine.exs:16` — `unique_index(:benchmark_suites, [:slug])`; `benchmark.ex:123` resolves suites by slug alone.

Expected (multi-tenant): tenants can create suites with the same slug; platform slugs stay reserved.
Actual: first tenant to claim a slug blocks everyone; `get_suite_by_slug` becomes ambiguous.

Fix (schema change — bundle here): composite unique index `[:workspace_id, :slug]` plus a partial/filtered mechanism keeping platform (NULL `workspace_id`) slugs globally unique, and a slug-resolution helper aware of tenancy. Requires a migration and adapter testing on both SQLite (local) and the cloud database.

## Acceptance criteria

- [ ] B1 decision made and implemented; benchmark API endpoints are tenant-scoped or fail closed in cloud mode, with tests for cross-tenant denial
- [ ] B2 policy decided, implemented, and documented
- [ ] B3 fails closed in cloud mode
- [ ] B4 caller audit done; unscoped entry points either converted or explicitly marked local-only
- [ ] B5 migration written and green on SQLite and cloud adapters; slug collisions between tenants resolve to distinct suites
- [ ] Local mode: all CLI benchmark commands behave exactly as before

## Sequencing

1. Land the companion web issue (Part A) first — A2's run-path guard reduces exposure of B4/B5 while this branch is open.
2. B1 → B2 → B3 → B4 → B5 in that order; B5 last since it is a migration.
