# security(cli/api): invitation token consumption atomicity, ordering, and rate-limiter server hygiene (PR #258 follow-up)

## Context

PR #258 (`security/invitation-lifecycle`, merge `e1296fae`) made cloud workspace enrolment consume the invitation and added per-IP throttling on the unauthenticated register endpoint. The web-side defects are tracked in the companion issue; this issue covers the **API, CLI-facing, and server-side** defects: a concurrency race that defeats the single-use guarantee, an ordering bug that burns invites on retryable failures, and rate-limiter memory/IP-derivation problems that only bite on a shared cloud deployment.

Cloud/web and CLI remain independent — this is not about replicating CLI features into the web. But `POST /cloud/v1/workspaces/register` is the enrolment endpoint CLI users hit against controlkeel.com from day one, so B1/B2/B4 are live on the shared cloud database at launch, not hypothetical future surface. B5/B6 are cleanup.

Full review: `pr-258-invitation-lifecycle-review.md`.

## Tasks

### B1 — TOCTOU race in `consume_invitation_for_enrolment/1` defeats single-use — 🔴 High

Evidence: `lib/controlkeel/accounts.ex:438-462` — the `Repo.get_by` check happens **outside** the transaction; the transaction only clears the hash. Two concurrent `POST /cloud/v1/workspaces/register` calls with the same token both read `pending` → both proceed → both bind a key to the org.

Expected: exactly one enrolment per invitation, even under concurrent calls from distinct IPs on distinct Fly nodes (the ETS limiter does not serialize them).
Actual: the single-use guarantee the PR exists to enforce is broken under concurrency — it's a plain DB race.

Fix: make consumption atomic with a single statement:

```elixir
{count, _} =
  Repo.update_all(
    from(m in Membership,
      where: m.invitation_token_hash == ^hash and m.status == "pending"
    ),
    set: [invitation_token_hash: nil, updated_at: DateTime.utc_now()]
  )
```

`count == 0` → `:invalid_token`; `count == 1` → re-fetch the row. (Equivalent alternative: `SELECT ... FOR UPDATE` inside the transaction.) Note `update_all` bypasses changesets — keep the `DateTime.truncate(:second)` convention. Add a concurrency test (two tasks racing the same token; exactly one succeeds).

### B2 — The invite is burned before enrolment completes — 🟠 Medium-high

Evidence: `lib/controlkeel_web/controllers/cloud_workspace_controller.ex:45-49` — pipeline order is `verify → resolve_invite (consumes!) → ensure_fingerprint_unused → enroll`. If the fingerprint conflicts, the key is revoked, or persistence fails, the invitation has already been consumed. Also, if the org row is gone, `consume` burns the token and only then does the controller return `:invalid_invite`.

Expected: a retryable enrolment failure does not consume a single-use credential.
Actual: a CLI user whose enrolment failed transiently (or who retried after a network error) must ask the operator for a new invitation.

Fix: reorder so `resolve_invite` runs last (after the fingerprint check); ideally consume inside the same transaction as `KeyRegistry.enroll` by passing the token/hash down. At minimum, document that enrol failures consume the invite.

### B3 — Rate-limiter ETS table grows without bound — 🔴 High (cloud ops)

Evidence: `lib/controlkeel/cloud/rate_limiter.ex` — buckets are never evicted (`reset/0` is test-only). PR #258 introduced per-IP keys (`ip:cloud_register:*`, `ip:invitation:*`); PR #260 added per-device-code keys. On a long-lived cloud node, every unique IP (IPv6 enumeration is trivial) creates a permanent ETS row — unbounded memory growth on an internet-facing service.

Expected: idle buckets are reclaimed; memory is bounded regardless of traffic diversity.
Actual: the table only ever grows; an attacker can pre-allocate rows at will by varying source IPs.

Fix: periodic sweep in the GenServer — `handle_info(:sweep)` scheduled via `Process.send_after/3` at boot, deleting buckets whose `last_ms` is older than N minutes (≥ burst/refill window; 1 hour is always safe). Do before/with cloud launch.

### B4 — "Per-IP" register throttle is a single global bucket behind Fly's proxy — 🔴 High (cloud ops)

Evidence: `ip_rate_limit.ex:53-59` keys on `conn.remote_ip`. On Fly.io (the documented deployment target — `rate_limiter.ex` moduledoc references Fly machines), `remote_ip` is the proxy's IP for **all** clients; `config/prod.exs:16` only sets `rewrite_on: [:x_forwarded_proto]` (scheme, not IP) and there is no `Fly-Client-IP` handling anywhere in the app. The register endpoint therefore gets one global bucket: >20 enrolments across **all tenants** in 40s → 429s for legitimate CLI users mid-onboarding.

Expected: per-client budgets in cloud mode; local mode unaffected (direct connections).
Actual: one shared bucket for everyone behind the proxy — both a lockout risk and a useless throttle (one attacker exhausts everyone's budget).

Fix: trust the edge — read `Fly-Client-IP` (Fly-specific) or `x-forwarded-for` at the outermost trusted boundary and rewrite `conn.remote_ip` once at the endpoint (small plug, documented trusted-proxy-only). Same root cause as companion issue A2: land one shared client-IP derivation helper and use it on both surfaces.

### B5 — Pre-migration invitations never expire (local installs) — 🟢 Low/Medium

Evidence: the migration (`20261012061352_add_invitation_expiry_to_memberships.exs`) adds nullable `expires_at` with no backfill, and `Membership.invitation_expired?/1` treats `nil` as never-expiring. Fine for cloud (fresh DB), but every existing local install keeps immortal pending tokens — the exact hazard the PR describes.

Fix options: (1) backfill `expires_at = invited_at + interval '14 days'` for pending rows in a follow-up migration; or (2) make `invitation_expired?/1` fall back to `invited_at` when `expires_at` is nil. At minimum, correct the moduledoc, which currently claims nil means "created outside the invite flow" — it also means every pre-migration invite.

### B6 — Trivial — 🟢 Trivial

- `ip_rate_limit.ex` moduledoc says "namespaced IP hash" — the IP is not hashed, just string-keyed. Fix wording (or actually hash, if you prefer not to store raw IPs in ETS).
- `RateLimiter.hit_key/2` guard `when not is_nil(key)` on a `term()` spec is odd but harmless — tighten or drop.

### Aside — `mix compile --warnings-as-errors` fails (pre-existing, not PR #258)

Warnings in `oauth_login_controller.ex`, `mcp/tools/ck_review_submit.ex`, `cli/dispatch/providers_budget.ex`, `benchmarks_live.ex`, `api_controller.ex` (the last two were modified on `fix/benchmark-tenancy` — re-check which remain). PR #258's files are warning-clean. Worth clearing before enforcing a strict CI gate at launch; can ride along with this issue or be tracked separately.

## Acceptance criteria

- [ ] B1: concurrent consumption of one token yields exactly one success (race test added); single-statement or locked consumption in `accounts.ex`
- [ ] B2: fingerprint conflict / revoked key / persistence failure does not consume the invitation; enrol-consume ordering fixed or documented
- [ ] B3: idle buckets are swept; memory bounded under synthetic unique-IP load; sweep test added
- [ ] B4: register throttle keys on the real client IP behind Fly's proxy (header-aware plug); local mode direct connections unchanged
- [ ] B5: backfill or invited_at fallback implemented, or moduledoc corrected to state the real nil semantics
- [ ] B6: wording/guard nits applied
- [ ] Local mode: CLI enrolment against a local server behaves as today; no CLI feature changes — this issue is server/API hygiene only

## Mode impact

- Cloud (controlkeel.com): B1 and B2 protect the live enrolment endpoint's security guarantee and retry UX; B3/B4 keep the rate limiter memory-bounded and per-client behind the proxy
- Local: no behavior change expected — direct connections, single user, bounded IP diversity; B5 only affects existing local DBs (positively, if backfilled)
