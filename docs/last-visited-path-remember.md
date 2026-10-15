## Summary

Remove the `/` landing/selector page for signed-in users and route them to their last-visited scoped path (Vercel-style). v1 stores the **whole path string** in **`localStorage`** only. Known loopholes (stale slugs, revocation, cross-device) are accepted for v1 and tracked as follow-ups below.

Signed-in users share one `/` home: the client navigates to the stored last path, else the default org; users with no orgs at all get an inline creation form on the same page (no separate shell/onboarding cases). Known loopholes (stale slugs, revocation, cross-device) are accepted for v1 and tracked as follow-ups below.

## Context / evidence

* `lib/controlkeel_web/router.ex:78` — `GET /` → `PageController.home`.
* `lib/controlkeel_web/controllers/page_controller.ex:20-37` — `/` branches: local → default org redirect; signed-in cloud → `selector_tree` render; anon → marketing `:home`.
* `lib/controlkeel_web/controllers/oauth_login_controller.ex:62-68` — post-login hard-redirects to `~/` (or invitation).
* `lib/controlkeel_web/live/auth_live.ex:40-46` — login page links back to `~/` (Home).
* Direction: delete global routes/layouts (`/dashboard`, `/sessions`, `/organizations`, `/policies`, `/skills`, `/benchmarks`, `/cloud/*`, `Layouts :dashboard`) and keep only scoped tree (`/:org_slug`, `/:org_slug/workspaces/:ws_slug`, `.../sessions/:id/*` under `OrganizationLayouts`) + `/auth/*` + `/invitations/*`.

## v1 scope

1. **Writer (client, route observer):** `app.js` observes the settled route (`DOMContentLoaded` + `phx:page-loading-stop`) and stores the trimmed overview root in `localStorage["ck.lastPath"]` — one observer covers switcher clicks, pasted URLs, bookmarks, back/forward, and full loads. No per-widget tagging. Top-level globals are never stored (reserved-slug exclusion); sub-routes trim to `/:org`, `/:org/workspaces/:ws`, or `.../sessions/:id`.
2. **Reader — `GET /`:** `/` stays the branding page for anon. `PageController.home` serves signed-in users one layout-less `app_home` template carrying `data-home-fallback` (default org path) and `data-home-has-orgs`. `app.js`: no orgs → reveal the inline creation form (stored path ignored as stale, e.g. all orgs deleted); otherwise `location.replace` to the re-parsed stored path or the fallback. Creation posts to `POST /orgs` (same controller): success lands on `/:slug`, failure re-renders with the form shown and an error. The server cannot read localStorage, so a pure 302 would lose the last path.
3. **Reader — post-login:** `OAuthLoginController.callback` keeps redirecting to `/` (find-or-create user only, no auto-provisioning); the shell resolves the last path from there, or the onboarding screen for memberless users. Invitation flow (`pending_invitation_token` → `/invitations/:token`) takes precedence, unchanged.
4. **Login page:** keep the Home link to `/` (`auth_live.ex:40-46`) — anon sees branding, signed-in users bounce via the shell, so the link stays correct for both.
5. **Logout:** `AuthController.logout` keeps clearing server session; boot/login JS clears `ck.lastPath` on explicit sign-out only (not on expiry).

## Non-goals (v1)

* No DB table, no Plug-session id triple, no cross-device sync.
* No slug-rename migration, no per-segment access pre-check beyond target LiveView's existing `OrgAccess`/`WorkspaceAccess`/session gates (target page re-enforces and redirects/fallbacks on failure).
* `/sessions/start` launcher stays global for v1 (resolves org/ws from query params as today).

## Accepted loopholes (tracked, not fixed in v1)

1. **Stale slug/renamed org/workspace** → stored path 404s; target LiveView shows not-found. Follow-up: hierarchical fallback (session → workspace → org → default).
2. **Revoked/deleted access** → stored path redirects then target gate bounces to login/org picker. Follow-up: pre-validate segments before redirect.
3. **Cross-device/new browser** → no memory (localStorage is per-browser). Follow-up: DB-backed `user_recent_contexts`.
4. **Multi-tab race** → last-write-wins, no timestamp. Follow-up: timestamp + debounce, write on settled mounts only.
5. **Open-redirect shape** → must validate `String.starts_with?(path, "/")`, reject `//`, `\`, external URLs (same `safe_return_to` policy as `auth_controller.ex:80-90`).

(Sub-route staleness is handled by design: the writer trims to overview roots, so `?launched=1`, `/tasks`, `/reviews/:rid` are never stored.)

## Acceptance criteria

* [ ] Signed-in visit to `/` never renders branding; shell `location.replace`s to last scoped path (or server-provided default fallback when empty).
* [ ] Browser close → reopen → `/` restores last path on same machine/browser.
* [ ] OAuth login lands on last path via the `/` shell (invitation flow unaffected).
* [ ] Anon `/` renders the branding page.
* [ ] Login page Home link points to `/` (branding for anon, shell bounce for authed).
* [ ] Legacy redirects (`/organizations/:slug`, `/sessions/:id`, observability/proof resolvers) keep working until sunset.
* [ ] `mix precommit` clean; targeted LiveView/controller tests for `/` boot redirect + callback redirect.

## Test plan

* `PageController` test: anon → branding 200; authed → shell 200 with `data-boot-fallback`; malformed fallback → `/organizations`.
* `OAuthLoginController` test: first signup provisions personal org; repeat login adds none; invitation token path.
* Switcher marker test: popover links carry `data-remember-path` with org-root hrefs.
