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

## Goal (as built — supersedes the original three-panel plan)

Move session observability under the organization layout as **one lean page with no tabs and no separate stage components**. During implementation the verbatim three-panel stack proved duplicative, so the page was deliberately reduced to what `Activity` and the session tabs don't already cover:

- **New route:** `GET /:org_slug/workspaces/:ws_slug/sessions/:id/observability` → `SessionObservabilityLive` (`OrganizationLayouts`, `:organization` live session), rendering inline `~H` (overview + event signals + memory, no `SessionObservability*` components — created during migration, then inlined and deleted).
- **Overview (inline, `id="observability-run-page"`):** budget decision/spend (`controlkeel obs run`), agent usage (invocations/est. cost/by-source/model/tool), one-line work-captured counts (tasks/proofs/memory), merged `What to do next` (`Enum.uniq(run ++ memory)` recommendations), `Download JSON envelope` button (`export.json`, `target="_blank"`). Health/findings/gates/recent-findings cards removed — canonical in session overview + `Findings`/`Reviews` tabs.
- **Event signals (inline, `id="session-observability-timeline"`):** summary only from `controlkeel obs timeline` (`Observability.timeline/1`): exact event-type breakdown, actor breakdown, window count/limit, up-to-3 proof-linked events (`Proof #id → /proofs/:id`, which Activity never surfaces), plus `Open full event feed → .../activity`. The 50-row event stream is **not** rendered here — canonical feed is `SessionActivityLive` (`.../activity`, same `SessionTranscript.recent_events` source).
- **Memory (inline, `id="session-observability-memory"`):** `controlkeel obs memory` summary (active/archived, context tasks/findings/reviews, by-type/source) + `Recent notes` as a `divide-y` list matching the Activity feed pattern.
- **Dedicated `observability_session` layout deleted.** `AGENTS.md` updated accordingly.
- **Legacy URLs redirect** via `PageController.observability_session_redirect/2` (lookup `Session` → `workspace.org.slug`/`workspace.slug` → redirect; `LocalDefaults` fallback in `:local`; `FallbackController.not_found` otherwise; `Ecto.Query.CastError` → 404). `/memory` preserves `#session-observability-memory`; **`/timeline` redirects to `.../activity`** (canonical feed), not to a dead anchor.

Exports:
- `export.json` dual-routed (legacy + org-scoped, `RequireSessionAuth`); download button lives on the observability page.
- `audit-log/:format` dual-routed (same controller/gate) but rendered **only in Activity** (`Audit exports`); the overview audit-export block was removed as duplicative.

Sidebar “Observability” is a real session nav item: `~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{id}/observability"` (TODO in `organization_layouts.ex` removed).

CLI parity (kept as a moduledoc note in `SessionObservabilityLive`): overview ≅ `controlkeel obs run <id>`, memory ≅ `controlkeel obs memory <id>`, envelope ≅ `controlkeel obs export <id>`, signals ≅ `controlkeel obs timeline <id>` (aggregates only).

## Non-goals

- No change to top-level `/observability` overview or any other observability section.
- No change to CLI, MCP, or catalog.
- `SessionActivityLive` keeps the canonical event feed and `Audit exports`; its stale `Full timeline → observability#...` card was deleted (the anchor it pointed to no longer renders a stream).

## Tasks

- [x] Migrate overview + memory content into `lib/controlkeel_web/live/session_observability_live.ex` (inline `~H`, no stage components)
  - Started as verbatim `SessionObservabilityOverview/Timeline/Memory` components (health, budget, findings, gates, hosts/models/tools, memory/proof/tasks, recommendations, trace + audit-log exports; `run`/`audit_exports`/`org_slug`/`ws_slug` props; `CommandPill`/tab links dropped), then inlined into the LiveView and deleted — component files intentionally do **not** exist in the final diff.
  - Final overview keeps: budget, agent usage, one-line work-captured counts, merged recommendations, `export.json` button. Removed: header title/session pill, health card, findings/gates cards, recent-findings list, jump-button row, jump/memory/proof links, audit-log export block (+ `audit_exports` assign, `Platform` alias, `format_exported_at/1`, unused `FormatHelpers` import).
  - Shared helpers: `neutral_pill_class/0` comes from `FormatHelpers` (imported via `html_helpers`); local `format_currency/1` + `format_frequency/1` only.

- [x] Add lean event-signals section (inline `id="session-observability-timeline"`)
  - Fetches `Observability.timeline(id, limit: 50)` but renders **aggregates only**: exact event-type breakdown, actor breakdown, window count/limit, up-to-3 proof-linked events, `Open full event feed → .../activity`. Full 50-row stream deliberately omitted (duplicates `SessionActivityLive`, same `SessionTranscript.recent_events` source).

- [x] Create `lib/controlkeel_web/live/session_observability_live.ex`
  - `use ControlKeelWeb, :live_view`, aliases `Accounts`, `Observability`, `SessionScope` (no `Platform`, no stage components)
  - `mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, ...)`:
    - `SessionScope.fetch_session(id)` → `Accounts.session_accessible?` → `SessionScope.check_scope` → `Observability.session_run/timeline/memory_context`
    - On success: `assign(:page_title, ...)`, `:org_slug/:ws_slug`, `:run/:timeline/:memory_context`, `assign_session_nav/2` (breadcrumbs: org → workspace → session → “Observability” plain text; `nav_org/nav_workspace/nav_session`)
    - On failure: `SessionScope.session_not_found(socket)` (`push_navigate` to `/`)
  - `render/1`: page header (`Session observability` + session title + export button) + overview + event signals + memory, all inline

- [x] Delete
  - `lib/controlkeel_web/live/observability_live.ex`
  - `lib/controlkeel_web/live/observability_timeline_live.ex`
  - `lib/controlkeel_web/live/observability_memory_live.ex`
  - `lib/controlkeel_web/components/layouts/observability_session.html.heex`
  - Migratory `lib/controlkeel_web/components/session_observability_{overview,timeline,memory}.ex` (created, then inlined and removed — absent from final diff)

- [x] Update `lib/controlkeel_web/router.ex`
  - Remove `live_session :observability_session` block (3 lives)
  - Add legacy redirects (browser scope, before `:organization` block):
    `get "/observability/sessions/:id"`, `/timeline`, `/memory` → `PageController.observability_session_redirect`
  - Inside `live_session :organization` block add:
    `live "/:org_slug/workspaces/:ws_slug/sessions/:id/observability", SessionObservabilityLive, :show`
  - In `scope "/", ControlKeelWeb, pipe_through: [:browser, :require_session_auth]`:
    keep legacy `get "/observability/sessions/:id/export.json"` and `"/audit-log/:format"` (dual-route)
    add `get "/:org_slug/workspaces/:ws_slug/sessions/:id/observability/export.json"` and `"/audit-log/:format"` → `ObservabilityController`

- [x] Update `lib/controlkeel_web/controllers/page_controller.ex`
  - Add `observability_session_redirect(conn, %{"id" => id})`: `Repo.get(Session, id)` → `Repo.preload(workspace: :org)` → `/memory` redirects to `"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{id}/observability#session-observability-memory"`, `/timeline` redirects to `"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{id}/activity"`, base id redirects to `.../observability`; `LocalDefaults` fallback in `:local`; `Ecto.Query.CastError` rescue → `FallbackController.not_found`

- [x] Update `lib/controlkeel_web/components/organization_layouts.ex`
  - Replace interim bridge: `href: ~p"/observability/sessions/#{session_id}"` → `~p"/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}/observability"` and remove TODO comment

- [x] Update `lib/controlkeel_web/live/session_activity_live.ex`
  - Delete the stale `Full timeline → observability#session-observability-timeline` card (anchor no longer renders a stream; Activity **is** the full feed); grid `lg:grid-cols-3` → `sm:grid-cols-2`
  - Audit-log links: `~p"/observability/sessions/#{@session.id}/audit-log/#{format}"` → `~p"/#{@nav_org.slug}/workspaces/#{@nav_workspace.slug}/sessions/#{@session.id}/observability/audit-log/#{format}"` (canonical home for audit exports)

- [x] Update `lib/controlkeel_web/components/recent_sessions.ex` — session observability link on the overview page
  - Direct org-scoped link `~p"/#{run.org_slug}/workspaces/#{run.workspace_slug}/sessions/#{run.id}/observability"` when `run` carries slugs; fallback to legacy path (redirect still works). Requires `Observability.overview_run_summary/1` + `session_summary/1` to expose `org_slug`/`workspace_slug` (`Map.get`-safe against `NotLoaded`).

- [x] Deduplicate stacked session observability (done — goes beyond the original plan)
  - Removed from overview: timeline preview, health/findings/gates/recent-findings cards, session pill + title header, jump-button row, jump/memory/proof links, full audit-log export block.
  - Removed full 50-row event stream (Activity canonical); kept exact-type/actor aggregates + proof-linked events only.
  - Merged run + memory recommendations into one `What to do next` (`Enum.uniq`); exports split by home (envelope here, audit-log in Activity); `neutral_pill_class` now shared via `FormatHelpers`; `Recent notes` uses `divide-y` like the Activity feed.

- [x] Update `AGENTS.md`
  - Framework layouts line: remove `:observability_session`, note organization layout and new session observability path

- [x] Tests
  - `test/controlkeel_web/live/observability_live_test.exs` hits the org-scoped path (`org_bound_session_fixture` + `observability_path/3`): asserts `#observability-run-page/costs/tools/recommendations/telemetry-export/memory-proof`, `#session-observability-timeline` + `#observability-timeline-summary` with `refute #observability-timeline-events`, `#session-observability-memory`; refutes health/findings/gates/recent/audit-log blocks; asserts new-path `export.json`, refutes overview audit-log href; covers legacy `export.json`, new-path envelope 200/404, and legacy redirects (`/timeline` → `.../activity`, `/memory` → `.../observability#session-observability-memory`)
  - Delete `observability_timeline_live_test.exs` and `observability_memory_live_test.exs`
  - Update `mission_control_live_test.exs` href to new path
  - Update `session_activity_live_test.exs`: refute `Full timeline` card, assert new audit-log hrefs
  - Update `recent_sessions_test.exs`: org-scoped href when slugs present, legacy fallback otherwise

## Acceptance

- `GET /observability/sessions/:id` → 302 `/:org_slug/workspaces/:ws_slug/sessions/:id/observability`; `/memory` → same with `#session-observability-memory`; `/timeline` → 302 `/:org_slug/workspaces/:ws_slug/sessions/:id/activity`; unknown or uncastable ids 404 via `FallbackController`
- `GET /:org_slug/workspaces/:ws_slug/sessions/:id/observability` renders overview (budget/usage/work-captured/recommendations/export) + event signals (aggregates + proof links, no stream) + memory under `OrganizationLayouts`, with correct breadcrumbs and session sidebar active state; missing/inaccessible/scope-mismatched → `Session not found.` redirect to `/`
- `export.json` works at both legacy and new paths; `audit-log/:format` works at both paths (rendered in Activity); `RequireSessionAuth` still gates them (cloud 302/404, local passthrough)
- `mix test` and `mix precommit` pass (observability subset green)
- No file under `lib/controlkeel_web/live/`, `lib/controlkeel_web/components/layouts/`, `lib/controlkeel_web/components/`, or `lib/controlkeel_web/router.ex` still references `:observability_session`, `ObservabilityLive`, `ObservabilityTimelineLive`, `ObservabilityMemoryLive`, or `/observability/sessions/:id` except as legacy redirect/dual-route/fallback

## Files in this change

- `AGENTS.md` — framework layouts note
- `lib/controlkeel/observability.ex` — `session_summary/1` + `overview_run_summary/1` expose `org_slug`/`workspace_slug` (nil-safe)
- `lib/controlkeel_web/components/layouts/observability_session.html.heex` — deleted
- `lib/controlkeel_web/components/organization_layouts.ex` — sidebar Observability href
- `lib/controlkeel_web/components/recent_sessions.ex` — direct org-scoped link + legacy fallback
- `lib/controlkeel_web/controllers/page_controller.ex` — new `observability_session_redirect/2` (`/timeline` → activity)
- `lib/controlkeel_web/live/session_activity_live.ex` — `Full timeline` card deleted; audit-log hrefs to new path
- `lib/controlkeel_web/live/session_observability_live.ex` — new inline LiveView (overview + signals + memory; no stage components)
- `lib/controlkeel_web/router.ex` — remove `live_session :observability_session`, add legacy redirects + new live + dual export routes
- `test/controlkeel_web/components/recent_sessions_test.exs` — href asserts
- `test/controlkeel_web/live/mission_control_live_test.exs` — href assert
- `test/controlkeel_web/live/observability_live_test.exs` — rewritten for lean inline page + redirect asserts
- `test/controlkeel_web/live/observability_memory_live_test.exs` — deleted
- `test/controlkeel_web/live/observability_timeline_live_test.exs` — deleted
- `test/controlkeel_web/live/session_activity_live_test.exs` — href asserts

## How to create the PR from base

```bash
git checkout feat/session-scoped-navigation
git checkout -b feat/session-observability-nesting
git cherry-pick c9a47330   # or apply the patch
# then the lean-page follow-ups in this branch (inline render, signals-only timeline, activity-owned audit exports)
mix test test/controlkeel_web/live/observability_live_test.exs
mix test
```

## Risks

- Large redirect surface (`/observability/sessions/*` → org-scoped/activity) — must preserve 302 for browser controllers and 404 for unknown ids; verified by tests (local + cloud-mode: anonymous callers get 401 regardless of id validity, cross-org members get 404).
- `PageController.observability_session_redirect` does a DB lookup (`Repo.get` + `Repo.preload`); it lives in the `:require_session_auth` scope (same gate as the exports) so the 302-vs-404 distinction is only visible to members — no unauthenticated existence oracle.
