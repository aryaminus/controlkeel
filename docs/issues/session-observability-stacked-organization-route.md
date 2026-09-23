# Session observability — stacked organization route

> **Ultimate goal:** [Navigation Modules Scope Alignment #130](https://github.com/aryaminus/controlkeel/issues/130) — **R4** (Session observability routes unify under `/sessions/:id/observability/*`; legacy `/observability/sessions/:id/*` redirects).
> This issue implements **R4 only**, stacked on `feat/session-scoped-navigation`. Org-scoped path `/:org_slug/workspaces/:ws_slug/sessions/:id/observability` is the `feat/session-scoped-navigation` realization of `/sessions/:id/observability`. R1–R3/R5 (Findings/Proofs moves, session chrome) stay out of scope.

> **Scope:** standalone task on top of `feat/session-scoped-navigation`.
> Isolates the session-observability nesting change as a single reviewable PR toward #130.

## Base

- **Base branch:** `feat/session-scoped-navigation`
- **Target PR branch:** `feat/session-observability-nesting` (or `feat/session-observability-stacked`)
- **Assumes codebase at base:** 18 observability LiveViews, standalone `/observability/sessions/*` with `:observability_session` layout and tab navigation (Overview / Timeline / Memory / Export).

## Background on base

On `feat/session-scoped-navigation`, session pages already live under `/:org_slug/workspaces/:ws_slug/sessions/:id/*` (overview, tasks, findings, reviews, deploy-review, activity, etc.) with `OrganizationLayouts` and `SessionScope` authorization.

Session observability is the **exception**: it still lives outside the organization layout:

- `GET /observability/sessions/:id` → `ObservabilityLive` (`:observability_session` layout, Overview)
- `GET /observability/sessions/:id/timeline` → `ObservabilityTimelineLive`
- `GET /observability/sessions/:id/memory` → `ObservabilityMemoryLive`
- `GET /observability/sessions/:id/export.json` and `/audit-log/:format` via `ObservabilityController` (browser + `RequireSessionAuth`)

Those three pages are **tabbed** (Overview / Timeline / Memory / Export JSON) via `components/layouts/observability_session.html.heex`. Sidebar “Observability” inside a session is a TODO interim bridge linking out to `/observability/sessions/:id`.

This breaks:
1. **Navigation consistency** — every other session tab is org-scoped; observability jumps to a top-level layout and loses breadcrumb/workspace switchers.
2. **Authorization model** — org-scoped pages use `SessionScope.check_scope/3` and `OrganizationLayouts` breadcrumbs; the standalone routes use a separate layout and manual `Accounts.session_accessible?` checks.
3. **Deep linking / history** — `/observability/sessions/:id` is disconnected from the session’s canonical URL.

## Goal

Move session observability under the organization layout and **stack** the three stages on one page — no tabs.

- **New route:** `GET /:org_slug/workspaces/:ws_slug/sessions/:id/observability` → `SessionObservabilityLive` (`OrganizationLayouts`, `:organization` live session)
- **Stacked stages:** Overview + Timeline + Memory rendered sequentially with anchors (`#session-observability-timeline`, `#session-observability-memory`) instead of tab navigation.
  - `SessionObservabilityOverview.overview_panel/1`
  - `SessionObservabilityTimeline.timeline_panel/1`
  - `SessionObservabilityMemory.memory_panel/1`
- **Dedicated `observability_session` layout deleted.** `AGENTS.md` updated accordingly.
- **Legacy URLs redirect** via `PageController.observability_session_redirect/2` (lookup `Session` → `workspace.org.slug`/`workspace.slug` → redirect; `LocalDefaults` fallback in `:local`; `FallbackController.not_found` otherwise; `Ecto.Query.CastError` → 404). Timeline/memory preserve anchors.

Exports keep working at both paths:
- Legacy: `GET /observability/sessions/:id/export.json` and `/audit-log/:format` (dual-route, no break for `controlkeel obs export` or old bookmarks)
- New: `GET /:org_slug/workspaces/:ws_slug/sessions/:id/observability/export.json` and `/audit-log/:format` (same controller, `RequireSessionAuth`)

Sidebar “Observability” becomes a real session nav item: `~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{id}/observability"` (fixes the TODO in `organization_layouts.ex`).

## Non-goals

- No change to top-level `/observability` overview or any other observability section.
- No change to CLI, MCP, or catalog.
- No change to `SessionActivityLive` beyond updating its timeline/audit-log links to the new anchors.

## Tasks

- [ ] Create `lib/controlkeel_web/components/session_observability_overview.ex`
  - Migrate verbatim from `ObservabilityLive` (health, budget, findings, gates, hosts/models/tools, memory/proof/tasks, recommendations, trace export, audit-log exports)
  - Props: `run`, `audit_exports`, `org_slug`, `ws_slug`
  - Drop `CommandPill` / tab links; timeline/memory “Open →” become `href="#session-observability-timeline"` / `href="#session-observability-memory"` anchors
  - Export/audit-log hrefs use `~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{run.session.id}/observability/..."`

- [ ] Create `lib/controlkeel_web/components/session_observability_timeline.ex`
  - Migrate verbatim from `ObservabilityTimelineLive` (`timeline_panel/1`, `neutral_pill_class`, `format_frequency`)
  - Outer section `id="session-observability-timeline"` + `scroll-mt-6`

- [ ] Create `lib/controlkeel_web/components/session_observability_memory.ex`
  - Migrate verbatim from `ObservabilityMemoryLive` (`memory_panel/1`)
  - Outer section `id="session-observability-memory"` + `scroll-mt-6`

- [ ] Create `lib/controlkeel_web/live/session_observability_live.ex`
  - `use ControlKeelWeb, :live_view`, aliases `Accounts`, `Observability`, `Platform`, three new components, `SessionScope`
  - `mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, ...)`:
    - `SessionScope.fetch_session(id)` → `Accounts.session_accessible?` → `SessionScope.check_scope` → `Observability.session_run/timeline/memory_context` + `Platform.list_audit_exports`
    - On success: `assign(:page_title, ...)`, `:org_slug/:ws_slug`, `:run/:timeline/:memory_context/:audit_exports`, `assign_session_nav/2` (breadcrumbs: org → workspace → session → “Observability” plain text; `nav_org/nav_workspace/nav_session`)
    - On failure: `SessionScope.session_not_found(socket)` (`push_navigate` to `/`)
  - `render/1`: header + three stacked panels

- [ ] Delete
  - `lib/controlkeel_web/live/observability_live.ex`
  - `lib/controlkeel_web/live/observability_timeline_live.ex`
  - `lib/controlkeel_web/live/observability_memory_live.ex`
  - `lib/controlkeel_web/components/layouts/observability_session.html.heex`

- [ ] Update `lib/controlkeel_web/router.ex`
  - Remove `live_session :observability_session` block (3 lives)
  - Add legacy redirects (browser scope, before `:organization` block):
    `get "/observability/sessions/:id"`, `/timeline`, `/memory` → `PageController.observability_session_redirect`
  - Inside `live_session :organization` block add:
    `live "/:org_slug/workspaces/:ws_slug/sessions/:id/observability", SessionObservabilityLive, :show`
  - In `scope "/", ControlKeelWeb, pipe_through: [:browser, :require_session_auth]`:
    keep legacy `get "/observability/sessions/:id/export.json"` and `"/audit-log/:format"` (dual-route)
    add `get "/:org_slug/workspaces/:ws_slug/sessions/:id/observability/export.json"` and `"/audit-log/:format"` → `ObservabilityController`

- [ ] Update `lib/controlkeel_web/controllers/page_controller.ex`
  - Add `observability_session_redirect(conn, %{"id" => id})` (as in commit `c9a47330`): `Repo.get(Session, id)` → `Repo.preload(workspace: :org)` → redirect to `"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{id}/observability"` with anchor `#session-observability-timeline` or `#...memory` when `conn.request_path` ends with `/timeline` or `/memory`; `LocalDefaults` fallback in `:local`; `Ecto.Query.CastError` rescue → `FallbackController.not_found`

- [ ] Update `lib/controlkeel_web/components/organization_layouts.ex`
  - Replace interim bridge: `href: ~p"/observability/sessions/#{session_id}"` → `~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}/observability"` and remove TODO comment

- [ ] Update `lib/controlkeel_web/live/session_activity_live.ex`
  - Timeline link: `~p"/observability/sessions/#{@session.id}/timeline"` → `~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/observability#session-observability-timeline"`
  - Audit-log links: `~p"/observability/sessions/#{@session.id}/audit-log/#{format}"` → `~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/observability/audit-log/#{format}"`

- [ ] Update `lib/controlkeel_web/live/observability_overview_live.ex` / `lib/controlkeel_web/components/recent_sessions.ex` — session observability link on the overview page
  - `RecentSessions.session_observability_section` currently links `~p"/observability/sessions/#{run.id}"` (legacy, 302 via `PageController.observability_session_redirect`)
  - Change to direct org-scoped link: `~p"/#{run.org_slug}/workspaces/#{run.workspace_slug}/sessions/#{run.id}/observability"` when `run` carries slugs; fallback to legacy path (redirect still works). Requires `Observability.overview_run_summary/1` to expose `org_slug`/`workspace_slug` from `run.session.workspace` (`workspace.slug` + `workspace.org.slug`, already preloaded via `Mission.get_session_context/1`).

- [ ] Deduplicate stacked session observability (overview + timeline + memory on one route) — remove repeated information/functions now that tabs are gone
  - **Overview `SessionObservabilityOverview.overview_panel/1` currently embeds previews that will repeat below:**
    - Timeline preview (`#observability-timeline` with `@run.timeline.recent` + “Open full timeline →”): duplicates `SessionObservabilityTimeline.timeline_panel/1` full stream (`#session-observability-timeline`). **Remove preview card** from overview; keep only an anchor link `href="#session-observability-timeline"` in the overview header or as a compact “Jump to timeline” button.
    - Memory/proof/tasks card (`#observability-memory-proof` with `memory.records`, types/sources): duplicates `SessionObservabilityMemory.memory_panel/1` summary (`#observability-memory-summary`, types/sources, active/archived). **Remove memory count/types from overview**; keep only the `href="#session-observability-memory"` anchor and the proofs count/link.
    - Recent findings / recent review gates grids duplicate the session’s `Findings`/`Reviews` nav pages and the timeline event stream. **Trim to at most one of**: either keep the two-card preview as a lightweight “Recent activity” summary, or remove and rely on the timeline + dedicated nav pages. Preference: keep a single “Recent findings” card (2–3 items) for at-a-glance health, drop the review gates grid (reviews already in timeline and in `SessionReviewsLive`).
  - **Keep single source for recommendations/exports:** audit-log/telemetry export cards stay only in overview (they are not in timeline/memory). Do not duplicate `format_frequency`/`format_currency` helpers — they already live in `FormatHelpers`.
  - **Result:** overview becomes lean (health, budget, gates, hosts/models/tools, one-line memory/proof/tasks with anchors, recommendations, exports); timeline and memory panels remain the canonical detailed views. Update `test/controlkeel_web/live/observability_live_test.exs` stacked asserts accordingly (overview no longer has `#observability-timeline` duplicate; timeline/memory remain `#session-observability-*`).

- [ ] Update `AGENTS.md`
  - Framework layouts line: remove `:observability_session`, note organization layout and new session observability path

- [ ] Tests
  - Update `test/controlkeel_web/live/observability_live_test.exs` to hit the new org-scoped path (use `org_bound_session_fixture` + `observability_path(org, ws, session)`), assert stacked IDs (`#observability-run-page`, `#session-observability-timeline`, `#session-observability-memory`), org-scoped export/audit-log hrefs, and legacy redirect asserts (302 to `/:org/.../observability` with anchors)
  - Delete `observability_timeline_live_test.exs` and `observability_memory_live_test.exs` (legacy LiveViews removed; stacked coverage moved into `observability_live_test.exs`)
  - Update `mission_control_live_test.exs` assert to new href
  - Update `session_activity_live_test.exs` asserts for timeline/audit-log hrefs

## Acceptance

- `GET /observability/sessions/:id` (and `/timeline`, `/memory`) 302 to `/:org_slug/workspaces/:ws_slug/sessions/:id/observability` (with correct anchor for timeline/memory); unknown or uncastable ids 404 via `FallbackController`
- `GET /:org_slug/workspaces/:ws_slug/sessions/:id/observability` renders the stacked page (overview + timeline + memory) under `OrganizationLayouts`, with correct breadcrumbs and session sidebar active state; missing/inaccessible/scope-mismatched → `Session not found.` redirect to `/`
- Exports work at both legacy and new paths; `RequireSessionAuth` still gates them (cloud 302/404, local passthrough)
- `mix test` and `mix precommit` pass (expect ~2515 tests, observability subset green)
- No file under `lib/controlkeel_web/live/`, `lib/controlkeel_web/components/layouts/`, `lib/controlkeel_web/components/`, or `lib/controlkeel_web/router.ex` still references `:observability_session`, `ObservabilityLive`, `ObservabilityTimelineLive`, `ObservabilityMemoryLive`, or `/observability/sessions/:id` except as legacy redirect/dual-route

## Files in this isolated change (17, 349+/312-)

- `AGENTS.md` — framework layouts note
- `lib/controlkeel_web/components/layouts/observability_session.html.heex` — deleted
- `lib/controlkeel_web/components/organization_layouts.ex` — sidebar Observability href
- `lib/controlkeel_web/components/session_observability_memory.ex` — new (from `observability_memory_live.ex`)
- `lib/controlkeel_web/components/session_observability_overview.ex` — new (from `observability_live.ex`)
- `lib/controlkeel_web/components/session_observability_timeline.ex` — new (from `observability_timeline_live.ex`)
- `lib/controlkeel_web/controllers/page_controller.ex` — new `observability_session_redirect/2`
- `lib/controlkeel_web/live/session_activity_live.ex` — links to new path/anchors
- `lib/controlkeel_web/live/session_observability_live.ex` — new stacked LiveView
- `lib/controlkeel_web/router.ex` — remove `live_session :observability_session`, add legacy redirects + new lives + dual export routes
- `test/controlkeel_web/live/mission_control_live_test.exs` — href assert
- `test/controlkeel_web/live/observability_live_test.exs` — rewritten for stacked org-scoped page + redirect asserts
- `test/controlkeel_web/live/observability_memory_live_test.exs` — deleted
- `test/controlkeel_web/live/observability_timeline_live_test.exs` — deleted
- `test/controlkeel_web/live/session_activity_live_test.exs` — href asserts
- `docs/issues/observability-route-consolidation.md` / `docs/observability-routes-report.md` — to be updated in this PR or left to a follow-up (optional for isolation)

## How to create the PR from base

```bash
git checkout feat/session-scoped-navigation
git checkout -b feat/session-observability-nesting
git cherry-pick c9a47330   # or apply the 17-file patch
# resolve only the AGENTS/docs conflicts by taking the base + the session-nesting note
mix test test/controlkeel_web/live/observability_live_test.exs
mix test
```

## Risks

- Large redirect surface (`/observability/sessions/*` → org-scoped) — must preserve 302 for browser controllers and 404 for unknown ids; verified by tests.
- `PageController.observability_session_redirect` does a DB lookup (`Repo.get` + `Repo.preload`); keep it outside the `:organization` live session so it stays a plain controller redirect (no LiveView mount cost).
