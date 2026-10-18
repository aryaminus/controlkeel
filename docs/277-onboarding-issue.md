## Summary

Three related changes, one PR (per the policy of removing unscoped global pages PR-by-PR):

1. **Org switcher gets a create/join entry** pointing at `/onboarding` (this branch's creation page).
2. **Delete the `/organizations` and `/sessions` global pages** — routes, dashboard-layout nav entries, and all in-app references.
3. **Sunset the removed URLs with redirects, not 404s** — old bookmarks keep working.

## Motivation / policy

Scoped routes (`/:org_slug/...`) are the app; global routes are legacy. Each removal PR deletes one page and repoints its references, keeping every intermediate state shippable. `/organizations` and `/sessions` are next because the switcher create button replaces the former's purpose and nothing replaces the latter's (global session list has no scoped equivalent — entry is always via org/workspace).

## Scope

### 1. Switcher create button → `/onboarding`

* `OrganizationLayouts.organization_sidebar` switcher popover gains a "Create organization" (and join-via-invite hint, invite links stay email-based) button linking to `~p"/onboarding"`.
* **Gate change required:** `LiveAuth.require_cloud_auth` currently bounces membered visitors off `/onboarding` back to `/`. A membered user clicking the new button must be allowed to *stay* and create an additional org (save already `push_navigate`s to the new slug). Redefine the gate: `/onboarding` admits all signed-in users; memberless users are fenced *onto* it (cannot leave to other gated views); membered users may visit to create, then leave via save.
* Update `OrgOnboardingLive` moduledoc + invert the "membered bounce" test in `org_onboarding_live_test.exs`.

### 2. Remove `/organizations` (`OrganizationsLive`) and `/sessions` (`MissionsLive`)

* Router: delete both `live` routes from the `:cloud_auth` session.
* Dashboard layout (`Layouts` `:dashboard`): drop the Organizations/Sessions nav items (and any children); breadcrumb `@label_map` entries may stay (harmless) or go.
* Repoint every `~p"/organizations"` and `~p"/sessions"` reference (compile-time verified — the build breaks until all are fixed, which is the checklist):
  * `LiveAuth` memberless redirect → `/onboarding`.
  * `AuthController.safe_return_to` defaults + `switch_org` failure target → `/` (resolves per-user from there).
  * `PageController` legacy resolvers (`{:organizations, msg}` outcomes) → `/`.
  * Per-LiveView `redirect_with_flash(..., ~p"/organizations")` fallbacks (~15 files: org/workspace/session/observability views) → `/` — or the nearest scoped parent where one is known.
  * UI links: dashboard "View all" sessions, `OnboardingLive` "View organizations" (`onboarding_live.ex:964`), empty states, user-menu entries.
  * Tests: `live_auth_test.exs` (exemption test goes away with the route), `organization_detail_live_test` switcher test (no `/organizations` href assertion), `page_controller_test` legacy-redirect describes stay (different routes), any `MissionsLive`/`OrganizationsLive` test files are deleted with their views.
* Delete `OrganizationsLive` + `MissionsLive` modules and templates (confirm no other callers: org-switch token minting in `OrganizationsLive.switch_org` event must move or go — the switcher in the org layout uses plain links, so the token flow dies with the page; verify nothing else mints `org-switch` tokens).

### 3. Sunset redirects (NOT 404) — the trap

Deleting the routes exposes the `/:org_slug` catch-all: `/organizations` would resolve as `org_slug: "organizations"`, fail lookup, and redirect to `/organizations` again — **an infinite client-side redirect loop** (same for `/sessions`; both slugs are in `Org.reserved_slugs`, so lookup always misses and always loops). Therefore, **before** the `:org_slug` block, add explicit sunset redirects:

* `GET /organizations` → `/` (fans out: membered → last/default path via shell; memberless → `/onboarding` via `home/2`).
* `GET /sessions` → `/` (same fan-out; the global list has no scoped equivalent, and `/` is the closest sane landing).

Both are one-line controller actions or `PageController` clauses; no new UI. This also fixes all legacy callers that still point at `/organizations` during migration (extra hop, still correct).

## Acceptance criteria

* [ ] Switcher popover shows a working create entry for membered and memberless users; save lands on the new org.
* [ ] No route, nav item, `~p` reference, or test points at `/organizations` or `/sessions` (except the two sunset redirects + legacy `/organizations/:slug` redirects, which stay).
* [ ] `GET /organizations` and `GET /sessions` 302 to `/` for anon (→ branding), membered (→ shell), and memberless (→ onboarding) — never 404, never loop (regression test both, asserting no self-redirect).
* [ ] Memberless users hitting any remaining gated view land on `/onboarding`; invitation flow unaffected.
* [ ] `mix precommit` clean.

## Out of scope

* Other globals (`/dashboard`, `/policies`, `/skills`, `/benchmarks`, `/cloud/*`, `:dashboard` layout itself) — later PRs, same pattern.
* Legacy `/organizations/:slug` + `/sessions/:id` resolver routes — stay until their own sunset.
* Cross-browser last-path tier — tracked separately.

## Open question

`/sessions` bookmark holders with many orgs land on `/` (last/default org) rather than any session list — accepted as the closest sane landing, since no scoped equivalent exists. Flag if a workspace-scoped "all sessions" index is wanted instead (bigger scope, not this PR).


ref: https://github.com/aryaminus/controlkeel/issues/277