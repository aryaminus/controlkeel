# Move remaining observability pages to workspace scope

## Summary

Move the 11 global `/observability/*` pages into the organization layout as `/:org_slug/workspaces/:ws_slug/observability` (overview) with subpages flat under the workspace (`/:org_slug/workspaces/:ws_slug/<page>`), following the benchmark precedent (issue #202 / PR #204). Status: moves + sidebar + GET resolvers done; mutation hardening + redirect/gate tests + precommit open (see slices).

## Motivation

Global `/observability/*` pages guess the workspace from the most recent session (`Mission.list_recent_sessions(1)`). In local mode with one workspace this looks like a whole-system view. In cloud mode with many workspaces per org it shows whichever workspace was active last — even one the viewer cannot access. Every remaining observability context function already accepts `workspace_id`, so the URL should say which workspace it shows.

## Current behavior (evidence)

Routes (`lib/controlkeel_web/router.ex:158-168`, `live_session :observability`, `:dashboard` layout): `live "/observability"`, `/loop`, `/compare`, `/costs`, `/evals`, `/imports`, `/memory-quality`, `/recommendations`, `/trends`, `/problems`, `/promotions`.

Mounts (`lib/controlkeel_web/live/observability_*_live.ex`): overview (`observability_overview_live.ex:12-14`), loop (`observability_loop_live.ex:12-13`), compare (`observability_compare_live.ex:14-15`), costs (`observability_costs_live.ex:19-20`), evals (`observability_evals_live.ex:12-13`), imports (`observability_imports_live.ex:12-13`), memory-quality (`observability_memory_quality_live.ex:12`), recommendations (`observability_recommendations_live.ex:12-13`), problems (`observability_problems_live.ex:12-13`), promotions (`observability_promotions_live.ex:12-13`) all do `Mission.list_recent_sessions(1) |> List.first()` → `[workspace_id: ...]`.

Unscoped risk: `list_recent_sessions(limit)` with `nil` workspace is an unscoped query (`mission.ex:712-719`, `cloud/scope.ex:42`), so cloud shows the last-active workspace globally. Benchmark redirect already fixed this pattern with `list_recent_sessions_for_user` (`page_controller.ex:232-237`).

Mutations: evals `save-candidates` (`observability_evals_live.ex:26-36`), loop `capture-perf-snapshot` persists a memory record (`observability_loop_live.ex:28-40`). Benchmark precedent gates mutations with `admin` (`observability_benchmark_live.ex:634-635`, `WorkspaceAccess.check` in `workspace_access.ex:28`).

Stale links: `problems_live.ex:175` still navigates to legacy `/observability/sessions/:id`.

Repro: in cloud with two workspaces, run a session in workspace B, then visit `/observability` — it shows B's data regardless of which workspace you came from.

## Expected behavior

1. New workspace routes (overview at `/:org_slug/workspaces/:ws_slug/observability`, subpages at `/:org_slug/workspaces/:ws_slug/<page>`) render the same sections/ids as before, mounted from the URL workspace (`get_workspace_by_slug` + `check_org_slug` + `WorkspaceAccess.check`, with `nav_org` / `nav_workspace` / `breadcrumbs`).
2. Roles: read-only pages gate `viewer`; evals save and loop snapshot gate `admin` (or gate only the button, not the read — do not repeat the benchmark side effect where viewers lost read access).
3. Params survive: trends `days` (`handle_params`/`push_patch`), memory-quality `stale_days`.
4. Old paths resolve via GET 302s (global `live` routes removed): `GET /observability` → workspace overview, `GET /observability/<page>` → flat workspace subpage, query preserved (pattern: `PageController.benchmark_workspace`), placed before the `:org_slug` catch-all. Workspace choice is the same selection as before but scoped to the viewer — local mode keeps `list_recent_sessions(1)` plus seeded defaults; cloud/self_hosted uses `list_recent_sessions_for_user(user, 1)` (most recent session among accessible workspaces, `mission.ex:731-738`); no accessible workspace or no sessions yet → `/organizations` picker.
5. Cloud auth on resolvers and pages (`live_auth.ex:36-63`): local passthrough; cloud anonymous → `/auth/login`; signed-in without membership → `/organizations` with flash; workspace pages additionally enforce `WorkspaceAccess.check`.
6. Links updated: problems legacy session link, `recent_sessions.ex` component, overview links, both sidebars (remove from dashboard `layouts.ex`, add group to workspace `organization_layouts.ex`). CLI `CommandPill` copy unchanged.

Non-goals: no context (`ControlKeel.Observability`) changes; no streaming/pagination; no CLI changes.

## Acceptance criteria

- [x] Each workspace URL returns 200 with content matching the old global page (live-test covered: overview/loop/evals/trends; uncovered renders: compare/costs/imports/memory/recommendations/problems/promotions).
- [~] Unknown/mismatched slugs bounce to `/organizations` with a flash; local mode unchanged (implemented, untested).
- [~] Each old `GET /observability/<page>` still resolves: authenticated users 302 to their workspace URL with query preserved; anonymous cloud users go to `/auth/login`; member-less users go to `/organizations` (implemented, untested).
- [x] Multi-workspace cloud check: resolver picks the most recent workspace the viewer can access, never one they cannot see (overview scoping test).
- [~] No `list_recent_sessions(1)` heuristic left in any moved mount — only scoped `(1, workspace.id)` lookups remain in costs/loop (resolvers use the `for_user` variant in cloud).
- [x] Sidebar + overview reference only workspace URLs (dashboard Observability group removed; `recent_sessions.ex` legacy fallback kept, its redirect still works).
- [~] Targeted live tests pass (45 related green); `mix precommit` not run yet.

## Implementation slices (in order; each mergeable)

1. [x] Read-only batch 1: overview, compare, costs, recommendations. Depends on: nothing.
2. [x] Read-only batch 2 with params: trends, memory-quality, problems, imports, promotions. Depends on: slice 1 (shared mount/redirect pattern).
3. [ ] Mutating pages hardening: evals, loop snapshot moved under `viewer` — role decision + gating open. Depends on: slices 1–2.
4. [~] Auth-aware GET resolvers + nav + link rewrites + tests done except: redirect tests, gate tests, live tests for 7 uncovered pages. Depends on: slices 1–3.

Branch: `feat/observability-workspace-scope`

## Test plan

- Done: per-page workspace live tests for overview/loop/evals/trends (render + events), updated `layouts_test.exs`, command-pill, recent-sessions and export suites — 45 related tests green.
- Open: `observability_page_redirect` assertions (`get(conn, "/observability/<page>")` → 302 + `Location`, query preserved) plus cloud cases (anonymous → login, member-less → `/organizations`, multi-workspace → most recent accessible, none → picker); gate tests (unknown slugs, viewer/admin); live tests for compare/costs/imports/memory/recommendations/problems/promotions.
- Full: `mix precommit` (compile, format, tests per repo config) — not run yet.

## Risks / notes

- Viewers losing read access if a whole page is gated `admin` — prefer `viewer` reads, `admin` mutations.
- Unscoped `list_recent_sessions(1)` in a resolver leaks the last-active workspace — resolvers must use `list_recent_sessions_for_user` in cloud.
- `GET` redirect order matters (before single-segment `:org_slug` lives and catch-all 404).
- Trends/memory-quality `push_patch` paths must use the new prefix.

## References

- Precedent: issue #202, PR #204, `observability_benchmark_live.ex:24-56`, `page_controller.ex:observability_page_redirect`, `live_auth.ex:36-63`
- Style: `docs/ui-style-guide.md`
