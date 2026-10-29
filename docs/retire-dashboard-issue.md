# Parent issue

link: https://github.com/aryaminus/controlkeel/issues/306

## Summary

Remove the last global "operator landing" page: retire `GET /dashboard` and `DashboardLive`, make the org overview page (`GET /:org_slug`, `OrganizationDetailLive`) the new dashboard, and teach the stats services it needs to answer per-org instead of globally.

Three coordinated changes, one PR (per the policy of removing unscoped global pages PR-by-PR — same policy as the `/organizations` and `/sessions` removals and the `/policies` → org-settings re-home):

1. **Delete the `/dashboard` route and page** — unknown-path access surfaces the shared invalid-org panel (the `/skills` precedent), not a redirect and not a silent 200.
2. **Org-scope the stats services** the dashboard used (`Analytics.funnel_summary/1`) so they can serve `/:org_slug` data.
3. **Rebuild the org overview as the dashboard** — org-scoped stat widgets above the existing workspaces grid / members tabs.

## Motivation / policy

Scoped routes (`/:org_slug/...`) are the app; global routes are legacy and will be retired route-by-route. `/dashboard` is the last global "front page": its metrics were computed across every org in the database and its provider/ACP panels describe project-runtime state with no org analog. The org root is already the de facto landing (root handoff sends membered users to their latest active org; `/new/org` save lands on the new slug), so promoting it to a real dashboard completes the migration instead of leaving a dead global page behind.

## Scope

### 1. Retire `/dashboard`

* Router (`lib/controlkeel_web/router.ex`): delete `live "/dashboard", DashboardLive, :index` from the `:cloud_auth` live_session. Add a route-site comment mirroring the `/skills` comment.
* Access behavior: `dashboard` is already in `Accounts.Org.@reserved_slugs`, so no org can ever occupy the URL. After deletion, `GET /dashboard` falls through to the `/:org_slug` live block and renders the shared invalid-org panel (same error shape as `/skills` — approved). Regression-test this in `test/controlkeel_web/router_test.exs`.
* Delete `lib/controlkeel_web/live/dashboard_live.ex` and `test/controlkeel_web/live/dashboard_live_test.exs`. Notes: the provider snapshot / ACP-registry panels die with the page — they are project-runtime concepts with no org analog; re-homing is deliberately a separate decision (see Out of scope).
* Repoint every dangling `/dashboard` reference to `/` (the root handoff already routes signed-in users to their latest active org, so `/` is the correct universal replacement — no new path helper needed). Compile-time verified: the build breaks until all are fixed, which is the checklist:
  * `components/layouts.ex`: remove the "Dashboard" sidebar nav item and the `"dashboard" => "Dashboard"` subnav label; drop the `show_dashboard` attr from the user menu and its conditional link; landing-header home icon `~p"/dashboard"` → `~p"/"`.
  * `components/layouts/public.html.heex`, `docs.html.heex`, `components/new_pages_layouts.ex`: same link + `show_dashboard` cleanup.
  * `live/invitation_live.ex`: four "Back to dashboard" links → `/` with the label "Back to home" (matching the existing signed-out branch).
  * `controllers/error_json.ex`: replace the stale "Generate keys at /dashboard under Workspaces > Service Accounts" hint with an org-scoped service-accounts pointer.

### 2. Org-scope the stats services

* `ControlKeel.Analytics.funnel_summary/1`: add an `:org_id` option. When set, the internal `recent_sessions/1` query joins through `workspace` and filters `org_id == ^org_id`; downstream math (steps, outcome metrics, findings density) is unchanged. `Mission.Session` already preloads `:workspace`, and `Mission.Workspace` carries `org_id`, so no schema or migration change.
* `ControlKeel.Benchmark.benchmark_summary` stays untouched: `Benchmark.Run` has no org/workspace linkage, so benchmark signal cannot be org-scoped yet — it is excluded from the org overview (documented limitation).
* Unit tests: `funnel_summary(org_id: ...)` never leaks another org's sessions into counts; empty org returns the "no data" defaults.

### 3. Org overview becomes the dashboard

* `OrganizationDetailLive` (`live "/:org_slug"`): on mount (and on org refresh in `maybe_refresh_org/2`), assign `ship_summary = Analytics.funnel_summary(org_id: org.id)`.
* New stat-card row above the org header meta, reusing the shipped card visual language (`rounded-2xl border bg-card shadow-card`, ring icons, progress bars) and the `format_percent` / `format_number` helpers ported from `DashboardLive`:
  * **Proof coverage** (`outcome_metrics.proof_backed_task_coverage_percent`)
  * **Deploy-ready rate** (`outcome_metrics.deploy_ready_task_rate_percent`)
  * **Finding density** (`average_findings_per_session`)
  * **Sessions** (`recent_session_count`)
  Empty values render "Not recorded", exactly as the old dashboard did.
* Page header (slug / members / budget / created), workspaces grid, members tab and all existing events stay unchanged.
* Extend `organization_detail_live_test.exs`: stat cards render with fixture data; empty-org defaults; no regression in members/workspace tabs.

## Acceptance criteria

* [ ] `GET /dashboard` renders the invalid-org error panel (regression test in `router_test.exs`); no route, LiveView, nav item, `~p` reference, or test points at `/dashboard` (grep gate: no `DashboardLive` or `~p"/dashboard"` left in `lib/`).
* [ ] Signed-in users have no path that lands on a dead page: `/` handoff, invitation flow, docs/public/new-page chrome all resolve to live targets.
* [ ] `Analytics.funnel_summary/1` accepts `:org_id`; org-filtered results are isolated per org (unit-tested).
* [ ] `/:org_slug` renders org-scoped stat cards (proof coverage, deploy-ready rate, finding density, sessions) above the unchanged workspaces grid and members tab.
* [ ] `mix precommit` clean.

## Out of scope

* **`/benchmarks` (explicitly out of scope per task owner)** — the `/benchmarks` and `/benchmarks/runs/:id` routes, `BenchmarksLive`, and `Benchmark`/`BenchmarkRun` schemas stay as-is. Benchmarks remain a global surface and are excluded from the org overview because `Benchmark.Run` has no org linkage.
* `/cloud/telemetry` and `/cloud/projects` (admin-only, cross-tenant; no org-scope analog yet — future retirement wave).
* Giving `Benchmark.Run` org ownership (a migration + invariant of its own).
* Re-homing the provider snapshot / ACP-registry status panels anywhere else.
* New public API endpoints for org stats — this task parameterizes the context functions only; API surface can follow once the widgets demand it.
