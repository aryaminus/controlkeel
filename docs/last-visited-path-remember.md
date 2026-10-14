## Summary

Remove the `/` landing/selector page for signed-in users and route them to their last-visited scoped path (Vercel-style). v1 stores the **whole path string** in **`localStorage`** only. Known loopholes (stale slugs, revocation, cross-device) are accepted for v1 and tracked as follow-ups below.

## Context / evidence

* `lib/controlkeel_web/router.ex:78` — `GET /` → `PageController.home`.
* `lib/controlkeel_web/controllers/page_controller.ex:20-37` — `/` branches: local → default org redirect; signed-in cloud → `selector_tree` render; anon → marketing `:home`.
* `lib/controlkeel_web/controllers/oauth_login_controller.ex:62-68` — post-login hard-redirects to `~/` (or invitation).
* `lib/controlkeel_web/live/auth_live.ex:40-46` — login page links back to `~/` (Home).
* Direction: delete global routes/layouts (`/dashboard`, `/sessions`, `/organizations`, `/policies`, `/skills`, `/benchmarks`, `/cloud/*`, `Layouts :dashboard`) and keep only scoped tree (`/:org_slug`, `/:org_slug/workspaces/:ws_slug`, `.../sessions/:id/*` under `OrganizationLayouts`) + `/auth/*` + `/invitations/*`.

## v1 scope

1. **Writer (client):** JS hook (`RememberLastPath`) on scoped pages writes `localStorage["ck.lastPath"]` on `handle_params` settlement, trimmed to the nearest **overview root** — never a sub-route, never a query string. Writes only under `/:org_slug/*`; never on `/auth/*`, `/invitations/*`, `/docs/*`. Trim rules:
   - `/:org_slug/**` → `/:org_slug` (e.g. `/:org_slug/settings` → `/:org_slug`)
   - `/:org_slug/workspaces/:ws_slug/**` → `/:org_slug/workspaces/:ws_slug`
   - `/:org_slug/workspaces/:ws_slug/sessions/:id/**` → `/:org_slug/workspaces/:ws_slug/sessions/:id`
2. **Reader — `GET /`:** `/` becomes a minimal boot LiveView (not a rendered page):
   - unauthenticated → redirect `/auth/login` (server decides via `LoadCurrentUser`).
   - authenticated → client pushes `ck.lastPath` via `push_event`; server validates same-origin path shape (`/org...` prefix, no `//`, no `\`) and redirects there; empty/missing → resolve `default_org_for_user` → first workspace → org page.
3. **Reader — post-login:** `OAuthLoginController.callback` redirects to validated `return_to`/`ck.lastPath` equivalent when present (via session `post_login_path` set by boot view), else `/` (which re-resolves). Invitation flow (`pending_invitation_token` → `/invitations/:token`) takes precedence, unchanged.
4. **Login page:** keep the Home link to `/` (`auth_live.ex:40-46`) — `/` is now a smart redirector to the last path, so the link stays correct.
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

* [ ] Signed-in visit to `/` never renders marketing/selector; lands on last scoped path (or deterministic default when empty).
* [ ] Browser close → reopen → `/` restores last path on same machine/browser.
* [ ] OAuth login lands on last path (invitation flow unaffected).
* [ ] Anon `/` → `/auth/login`.
* [ ] Login page Home link points to `/` (redirects to last path).
* [ ] Legacy redirects (`/organizations/:slug`, `/sessions/:id`, observability/proof resolvers) keep working until sunset.
* [ ] `mix precommit` clean; targeted LiveView/controller tests for `/` boot redirect + callback redirect.

## Test plan

* `PageController`/`boot LiveView` test: anon → login; auth + valid stored path → 302/navigate; malformed/external path → default.
* `OAuthLoginController` test: with/without `post_login_path`, with invitation token.
* JS hook test (if harness exists): writes only on scoped paths, trims sub-routes to overview roots, clears on logout.
