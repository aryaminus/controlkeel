<!-- Suggested title: fix(web): invitation lifecycle — rate-limit crash, shared IP bucket, dead re-invites (PR #258 follow-up) -->
<!-- Suggested labels: security, web, cloud-launch-blocker -->
<!-- Suggested base branch: fix/benchmark-tenancy (all findings re-verified valid at 215656f0) -->
<!-- Companion issue: CLI/API/server follow-up tracked separately (docs/issue-cli-api-invitation-lifecycle-followup.md) -->

# fix(web): invitation lifecycle — rate-limit crash, shared IP bucket, dead re-invites (PR #258 follow-up)

## Context

PR #258 (`security/invitation-lifecycle`, merge `e1296fae`) added invitation expiry (default 14 days), single-use cloud enrolment, and per-IP throttling on the two unauthenticated token oracles. The core ideas are correct and its tests pass — but the review found the throttling is broken in ways that make it worse than no throttle, one invitation path produces dead-on-arrival invites, and the new expiry is invisible to users. Full review: `pr-258-invitation-lifecycle-review.md`.

Scope of this issue: **web surfaces only** (LiveViews, the members UI, invitation page, mailer payload, and the shared web-side throttle). CLI/API/server items are deliberately out of scope here — web/cloud remain independent of CLI feature replication; those are tracked in the companion follow-up issue. This issue is the fix-now set before controlkeel.com goes live.

All findings re-verified valid on `fix/benchmark-tenancy` @ `215656f0`; line references below match that branch.

## Tasks

### A1 — Rate-limited invitation page crashes (`FunctionClauseError`) — 🔴 High

Evidence: `lib/controlkeel_web/live/invitation_live.ex:39-46` — when the bucket is empty, `mount` assigns only `:page_title` and `:rate_limited`, **no `:state`**. Every `render/1` clause pattern-matches on `state` (`:ready` / `:already_accepted` / `:invalid` / `:error`); there is no fallback clause.

Expected: the visitor sees the intended "Too many invitation lookups" flash.
Actual: the LiveView raises at render — a hard error page in the HTTP pass, a crashed WS process in production. `:rate_limited` is assigned but consumed by nothing. No test covers this path (`test/controlkeel/invitation_lifecycle_test.exs` only tests `Accounts` functions).

Fix: add a `render(%{state: :rate_limited})` clause — a restrained card consistent with the existing `:invalid` state per `docs/ui-style-guide.md`. The `:invitation` layout already renders `<.flash_group>`, so the flash displays once render succeeds. Add a LiveView test that mounts with an exhausted bucket.

### A2 — Every visitor shares ONE rate-limit bucket — 🔴 High (cloud-launch blocker)

Two compounding defects:

1. `invitation_live.ex:50-54` reads `connect_info.remote_ip`, but `endpoint.ex:25-27` configures `websocket: [connect_info: [session: @session_options]]` — there is no `:peer_data` and no `remote_ip` key, so the clause never matches and every client gets `"unknown"` as its key (`ip:invitation:unknown`). One global bucket: burst 20, refill 0.5/s.
2. `mount` runs twice per page view (HTTP dead-render pass + WebSocket-connect pass) and again on every reconnect. The comment at `:29-31` claiming "The WebSocket reconnect does not re-run mount" is factually wrong.

Expected: per-client throttling that survives cloud-mode traffic.
Actual: after ~10 invitation page views globally in a short window (20 tokens ÷ 2 per view), the entire invitation-acceptance flow locks for everyone — and per A1, that lock is a crash, not a message. This is the onboarding surface for controlkeel.com.

Fix: (a) add `:peer_data` (+ `:x_headers` if TLS terminates behind a proxy) to the socket's `connect_info` and derive the IP from `peer_data.address`; (b) gate the throttle on `connected?(socket)` so only the WS pass consumes a token, or double the burst to account for the double mount; (c) correct the comment; (d) test that distinct IPs get distinct buckets.

Shared root cause with companion issue item B4 (register throttle keys on the proxy IP) — land the client-IP derivation helper once, use it on both surfaces.

### A3 — Re-inviting a revoked member produces a dead-on-arrival invitation — 🔴 High

Evidence: `lib/controlkeel/accounts.ex:326-338` — the `revoked` branch of `invite_member` (reachable from the web: Organization Settings → Invite, `organization_settings_live.ex:165`) resets role, token hash, `invited_at`, etc., but **does not set `expires_at`**. If the original invitation expired, the stale past `expires_at` survives the re-invite and the new token is rejected instantly by `accept_invitation/2` and `lookup_invitation/1`.

Expected: a re-issued invitation behaves like a fresh one.
Actual: the operator sees a fresh token / "invitation sent"; the invitee sees "Invitation not found". Functional regression introduced by PR #258 (`expires_at` did not exist before it). Also hits the `cloud_selfhost` CLI dispatch path (companion issue notes the same fix).

Fix: add `expires_at: expires_at` to the revoked-branch changeset. Test: revoke → force expiry into the past → re-invite → accept must succeed.

### A4 — The 14-day expiry is invisible in every UI surface — 🟡 Medium

Evidence: no surface mentions expiry — not the invite modal/token banner (`organization_settings_live`), not the members table pending rows, not the invitation preview (`invitation_live.ex` `:ready` shows only org + role), not the email payload (`mailer.ex:36` passes only `email`, `token`, `url`).

Expected: invitees and operators can see an invitation's deadline.
Actual: invitees hit "Invitation not found" with no hint the invite aged out; operators can't distinguish a broken link from an expired one — a guaranteed support-ticket pattern at cloud launch.

Fix: show "Expires <date>" on the invitation preview and pending member rows; include the expiry in the mailer payload. Cheap, high UX return.

### A5 — Missing test coverage + latent test flakiness for the throttle layer — 🟡 Medium

Evidence:

- No test for the `IpRateLimit` plug (429, `Retry-After`, bucket isolation), no router-level 429 test for `:cloud_register`, no LiveView rate-limit test (A1 is the proof of cost).
- `test/controlkeel_web/controllers/cloud_workspace_controller_test.exs` posts to `/cloud/v1/workspaces/register` ~9 times with **no `RateLimiter.reset()` in setup** — the bucket for `{127,0,0,1}` persists across the whole suite. Today 9 < burst 20, so it passes; adding a few register tests or changing seeds will produce order-dependent 429s in CI.

Fix: add `RateLimiter.reset()` to the register test setup; add plug and LiveView tests.

### A6 — `invitation_expiry/2` has dead code and silent degradation — 🟢 Low

Evidence: `accounts.ex:246-271` — the binary-string parsing branch is copied from the service-account API pattern (`platform.ex:1223`), but memberships are only created from internal callers passing integer opts. Error semantics are also inverted vs `platform.ex`: there invalid `expires_in_days` is an error; here a non-positive integer or bad config (`invitation_expiry_days: 0`) silently produces `nil` = an immortal invitation.

Fix: drop the binary branch (accept integer only); make invalid config fail loudly (log warning or raise at boot) rather than silently disabling expiry.

### A7 — Duplicated throttle constants and key-building — 🟢 Low/optional

Evidence: the IP-key construction and burst/refill literals (20 / 0.5) are duplicated between `ip_rate_limit.ex` and `invitation_live.ex:32-34` and will drift. The expired-check-and-map-to-`:invalid_token` logic appears three times in `accounts.ex` (lookup/consume/accept).

Fix: extract a shared hit helper (e.g. `ControlKeelWeb.Plugs.IpRateLimit.hit(bucket, ip, opts)`) reused by both surfaces; one private helper for the expiry check in `accounts.ex`. Not blocking.

## Acceptance criteria

- [ ] A1: exhausting the bucket renders the friendly rate-limited state (no crash); covered by a LiveView test
- [ ] A2: distinct client IPs get distinct buckets (socket fixture test); the throttle consumes one token per page view, not two; the mount comment matches actual LiveView behavior
- [ ] A3: revoke → expired → re-invite → accept succeeds; regression test added
- [ ] A4: invitation preview, pending member rows, and the invitation email show the expiry date
- [ ] A5: register test setup calls `RateLimiter.reset()`; plug and router-level 429 tests added
- [ ] A6–A7: applied (A7 may be folded into A2's shared IP/throttle helper)
- [ ] Local mode: invitation page and re-invite flows behave identically to today except for the crash fix (A1) and fresh re-invite expiry (A3)

## Mode impact

- Cloud (controlkeel.com): unblocks onboarding — the invitation page no longer globally locks/crashes (A1, A2), re-invites work (A3), expiry is visible (A4)
- Local/self-hosted: single-user buckets make A2 harmless locally, but A1 and A3 affect local web UIs too — both fixed here
