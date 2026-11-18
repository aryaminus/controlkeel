# Review: PR #258 (`security/invitation-lifecycle`) as merged into main

**Scope reviewed:** merge commit `e1296fae` (branch tip `8b5eb9d9`), 9 files, +383/−20. Verified against current main state (later PRs touched neighboring code but not these behaviors, except where noted).

**Verified healthy:** targeted tests pass (14/14 in `invitation_lifecycle_test.exs` + `cloud_workspace_controller_test.exs`); router has no duplicate `/workspaces/register` route; the invitation layout already renders `<.flash_group>`; register route correctly moved out of the telemetry-ingest budget. The core idea of each change (expiry, single-use enrolment, per-IP throttle) is right and the code quality is generally good.

---

## Part A — Web service, features, UI/UX (fix now)

### A1 — 🔴 High: Rate-limited invitation page crashes (`FunctionClauseError`)
`lib/controlkeel_web/live/invitation_live.ex:39-46` — when the bucket is empty, `mount` assigns only `:page_title` and `:rate_limited` **but no `:state`**. Every `render/1` clause in the module pattern-matches on `state` (`:ready`, `:already_accepted`, `:invalid`, `:error`); there is no fallback clause. Result: instead of the intended "Too many invitation lookups" flash, the LiveView **raises at render** — the user gets a hard error page, and in production the WS process crashes. `:rate_limited` is assigned but consumed by nothing.

**Why it matters:** the throttle was added to protect users; as shipped, hitting the throttle produces a worse experience than the attack it defends against — and no test covers this path (`invitation_lifecycle_test.exs` only tests `Accounts` functions).

**Recommendation:** add a `render(%{state: :rate_limited})` clause (a restrained card consistent with the existing `:invalid` state, per `docs/ui-style-guide.md`), and add a LiveView test that mounts with an exhausted bucket. The layout already renders `flash_group`, so the flash will display once render succeeds.

### A2 — 🔴 High (cloud-launch blocker): Every visitor shares ONE rate-limit bucket
Two compounding defects in the LiveView throttle:

1. `invitation_live.ex:50-54` reads `connect_info.remote_ip`, but `endpoint.ex:25-27` configures `websocket: [connect_info: [session: @session_options]]` — **there is no `:peer_data` and no `remote_ip` key**, so the pattern never matches and every client on earth gets `"unknown"` as its key (`ip:invitation:unknown`). One global bucket: burst 20, refill 0.5/s.
2. `mount` runs **twice per page view** (the HTTP dead-render pass and the WebSocket-connect pass), and again on every WS reconnect. The comment at lines 29-31 claiming "The WebSocket reconnect does not re-run mount" is factually wrong — every WS connect/reconnect runs `mount`.

**Why it matters:** in cloud mode at controlkeel.com, after ~10 invitation page views globally in a short window (20 tokens ÷ 2 per view), **the entire invitation-acceptance flow locks for everyone** — and per A1, that lock is a crash, not a message. This is exactly the surface you'll drive new-tenant onboarding through. Local mode is unaffected in practice (single user, 127.0.0.1).

**Recommendation:** (a) add `:peer_data` (+ `:x_headers` if you terminate TLS behind a proxy) to the socket's `connect_info` and derive the IP from `peer_data.address`; (b) gate the throttle on `connected?(socket)` so only the WS pass consumes a token (or double the burst to account for the double mount); (c) correct the comment; (d) test with a fixture that asserts distinct IPs get distinct buckets.

### A3 — 🔴 High: Re-inviting a revoked member produces a dead-on-arrival invitation
`lib/controlkeel/accounts.ex:326-338` — the `revoked` branch of `invite_member` (reachable from the web UI: Organization Settings → Invite, `organization_settings_live.ex:165`) resets role, token hash, `invited_at`, etc., but **does not set `expires_at`**. If the original invitation expired, the stale past `expires_at` survives the re-invite — the new token is rejected instantly by `accept_invitation` and `lookup_invitation`.

**Why it matters:** the operator sees a fresh token / "invitation sent", the invitee sees "Invitation not found". This is a functional regression introduced by this PR (before it, `expires_at` didn't exist). It also hits the `cloud_selfhost` CLI dispatch path (Part B side-effect, same fix).

**Recommendation:** add `expires_at: expires_at` to the revoked-branch changeset, and add a test: revoke → let expiry pass → re-invite → accept must succeed.

### A4 — 🟡 Medium: The 14-day expiry is invisible in every UI surface
No surface mentions expiry: not the invite modal/token banner (`organization_settings_live`), not the members table pending rows, not the invitation preview page (`invitation_live.ex` `:ready` state shows only org + role), not the email payload (`mailer.ex:36` passes only `email`, `token`, `url`).

**Why it matters:** invitees will hit "Invitation not found" with zero hint that the invite aged out — a guaranteed support ticket pattern at cloud launch, and operators can't tell a broken link from an expired one.

**Recommendation:** show "Expires <date>" on the invitation preview and pending member rows; include the expiry in the mailer payload. Cheap, high UX return for cloud onboarding.

### A5 — 🟡 Medium: Missing test coverage + latent test flakiness for the throttle layer
- No test for the `IpRateLimit` plug (429, `Retry-After`, bucket isolation), no router-level 429 test for `:cloud_register`, no LiveView rate-limit test (A1 proves the cost).
- `cloud_workspace_controller_test.exs` posts to `/cloud/v1/workspaces/register` ~9 times **without `RateLimiter.reset()` in setup** — the bucket for `{127,0,0,1}` persists across the whole suite. Today 9 < 20 so it passes, but adding a few register tests or changing seeds will produce mysterious, order-dependent 429s in CI.

**Recommendation:** add `RateLimiter.reset()` to the register test setup; add plug and LiveView tests.

### A6 — 🟢 Low: `invitation_expiry/2` has dead code and silent degradation
`accounts.ex:246-271` — the binary-string parsing branch is copied from the service-account API pattern (`platform.ex:1223`), but memberships are only ever created from internal callers passing integer opts; no caller sends strings. Worse, the error semantics are inverted vs. `platform.ex`: there, invalid `expires_in_days` is an error; here, a non-positive integer or bad config (`invitation_expiry_days: 0`) **silently produces `nil` = an immortal invitation**.

**Recommendation:** drop the binary branch (accept integer only), and make invalid config fail loudly (log warning or raise at boot) rather than silently disabling expiry.

### A7 — 🟢 Low/optional: Duplicated throttle constants and key-building
The IP-key construction and burst/refill literals (20 / 0.5) are duplicated between `ip_rate_limit.ex` and `invitation_live.ex:32-34`, which will drift. Extract a shared helper (e.g., `ControlKeelWeb.Plugs.IpRateLimit.hit(bucket, ip, opts)` reused by both surfaces). Similarly, the expired-check-and-map-to-`:invalid_token` logic now appears three times in `accounts.ex` (lookup/consume/accept) — one private helper would read better. Not blocking.

---

## Part B — CLI, API, server (follow-up; document as issues now)

### B1 — 🔴 High (security, defeats the PR's own goal): TOCTOU race in `consume_invitation_for_enrolment/1`
`accounts.ex:438-462` — the `Repo.get_by` check happens **outside** the transaction; the transaction only clears the hash. Two concurrent `POST /cloud/v1/workspaces/register` calls with the same token both read `pending` → both proceed → both bind a key to the org. The single-use guarantee the PR exists to enforce is broken under concurrency (and across Fly nodes it's just a DB race — the ETS limiter doesn't serialize distinct IPs).

**Recommendation:** make consumption atomic — a single statement is both simpler and race-free:
```elixir
{count, _} =
  Repo.update_all(
    from(m in Membership,
      where: m.invitation_token_hash == ^hash and m.status == "pending"
    ),
    set: [invitation_token_hash: nil, updated_at: DateTime.utc_now()]
  )
```
`count == 0` → `:invalid_token`; `count == 1` → re-fetch the row. (Or `SELECT ... FOR UPDATE` inside the transaction.) Add a concurrency test. Note `update_all` bypasses changesets, so validate the timestamp truncation.

### B2 — 🟠 Medium-high: The invite is burned before enrolment completes
`cloud_workspace_controller.ex:45-49` — pipeline order is `verify → resolve_invite (consumes!) → ensure_fingerprint_unused → enroll`. If fingerprint conflicts, the key is revoked, or persistence fails, the invitation has already been consumed — the CLI user must ask for a new invite after a transient/retryable failure. Also, if the org row is gone, `consume` burns the token and then the controller returns `:invalid_invite`.

**Recommendation:** reorder so `resolve_invite` runs last (after the fingerprint check), and ideally consume inside the same transaction as `KeyRegistry.enroll` (pass the token/hash down). At minimum, document that enrol failures consume the invite.

### B3 — 🔴 High (cloud ops): Rate-limiter ETS table grows without bound
`cloud/rate_limiter.ex` — buckets are never evicted (`reset/0` is test-only). This PR introduced per-IP keys (`ip:cloud_register:*`, `ip:invitation:*`); PR #260 added per-device-code keys. On a long-lived cloud node, every unique IP (IPv6 enumeration is trivial) creates a permanent ETS row — an unbounded memory growth vector exactly when the service becomes internet-facing.

**Recommendation:** add a periodic sweep in the GenServer (`handle_info(:sweep)`, `Process.send_after` at boot) deleting buckets whose `last_ms` is older than N minutes (last-touch ≥ burst/refill window, e.g. 1 hour, is always safe). Keep it in Part B but do it before/with launch.

### B4 — 🔴 High (cloud ops): "Per-IP" register throttle is a single global bucket behind Fly's proxy
`ip_rate_limit.ex:53-59` keys on `conn.remote_ip`. On Fly.io (the documented deployment target — `rate_limiter.ex` moduledoc mentions Fly machines), `remote_ip` is the proxy's IP for **all** clients; `config/prod.exs` only sets `rewrite_on: [:x_forwarded_proto]` (scheme, not IP) and there's no `Fly-Client-IP` handling anywhere. So the register endpoint gets one global bucket: >20 enrolments across **all tenants** in 40s → 429s for legitimate CLI users mid-onboarding.

**Recommendation:** trust the edge: read `Fly-Client-IP` (Fly-specific) or `x-forwarded-for` at the outermost trusted boundary and rewrite `conn.remote_ip` once at the endpoint (a small plug, documented as trusted-proxy-only). This is the same root cause as A2 — one shared "client IP derivation" fix should serve both surfaces. Local mode: unaffected (direct connections).

### B5 — 🟢 Low/Medium: Pre-migration invitations never expire (local installs)
The migration adds a nullable `expires_at` with no backfill, and `invitation_expired?` treats `nil` as never-expiring. Fine for cloud (fresh DB), but every local mode install keeps immortal pending tokens — the exact hazard the PR describes. Acceptable to leave, but record it: either backfill `expires_at = invited_at + 14d` for pending rows in a follow-up migration, or make `invitation_expired?/1` fall back to `invited_at` when `expires_at` is nil. At minimum, document the choice in the moduledoc (it currently says nil means "created outside the invite flow", which is not the whole truth).

### B6 — 🟢 Trivial
- `ip_rate_limit.ex` moduledoc says "namespaced IP hash" — the IP is not hashed, just string-keyed. Fix wording (or actually hash if you prefer not to store IPs in ETS).
- `hit_key/2` guard `when not is_nil(key)` on a `term()` spec is odd but harmless.

### Aside (pre-existing on main, not this PR)
`mix compile --warnings-as-errors` currently **fails on main** from warnings in unrelated files (`oauth_login_controller.ex`, `mcp/tools/ck_review_submit.ex`, `cli/dispatch/providers_budget.ex`, `benchmarks_live.ex`, `api_controller.ex`). The PR #258 files are warning-clean. Worth clearing before you enforce a strict CI gate at launch.

---

## Summary

**Fix first (all small, high-value; good candidates for one branch on top of `fix/benchmark-tenancy`):**
1. **A1 + A2 (+B4's root cause)** — invitation page crashes and globally locks; register throttle keys on the proxy IP. One issue: "derive real client IP + render rate-limited state" — the `connect_info`/`Fly-Client-IP` fix and the missing `render/1` clause together unblock cloud onboarding.
2. **A3** — re-invite must stamp a fresh `expires_at` (web flow is broken for expired→re-invited members).
3. **B1** — atomic token consumption (single `UPDATE ... WHERE`); this is the security property the PR promises.
4. **B2** — consume the invite only after enrolment checks pass.
5. **B3** — ETS bucket sweep before/with cloud launch.

**Optional / follow-up:** A4 (surface expiry in UI/email — recommended before launch but not blocking), A5 (tests + `RateLimiter.reset()` in register test setup), A6 (simplify `invitation_expiry/2`), A7/A8 (dedupe helpers), B5 (backfill or document nil-expiry), B6 (wording).

**Mode impact check:** local mode keeps working for everything here (single-user buckets, direct connections); A3 and A1 also affect local/self-hosted web UIs, so they belong in Part A regardless. A2, B3, B4 only bite at cloud scale — but they bite hard exactly at the moment you flip controlkeel.com live.
