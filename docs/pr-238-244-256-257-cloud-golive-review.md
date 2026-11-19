# Review: PRs #257, #256, #244, #238 as merged into main — pre-cloud-go-live (controlkeel.com)

**Scope reviewed:** the four security branches merged on Nov 3 ahead of the controlkeel.com launch:

| PR   | Branch                               | Merge      | Branch tip | Files                                                                                                                |
| ---- | ------------------------------------ | ---------- | ---------- | -------------------------------------------------------------------------------------------------------------------- |
| #257 | `security/hosted-authz-fails-closed` | `bbca3ed6` | `4ce2ad2d` | `config/runtime.exs`, `mcp/protocol_interop.ex`, `controllers/api_helpers.ex`, + new test                            |
| #256 | `security/cloud-key-revocation`      | `0f0fd2d2` | `6d1b8016` | `cloud/workspace/key_registry.ex`, `controllers/cloud_workspace_controller.ex`, + test                               |
| #244 | `security/oauth-email-verification`  | `7c5bfe9f` | `5e26ab34` | `accounts/oauth_providers.ex`, `oauth_providers/default_adapter.ex`, `controllers/oauth_login_controller.ex`, + test |
| #238 | `security/api-auth-constant-time`    | `8ee35a22` | `e03f8143` | `plugs/api_auth.ex`, + new test                                                                                      |

**Important context:** PR #257's break-glass design (`CONTROLKEEL_BREAK_GLASS_*` env vars, `authorize_bootstrap/3` in `APIHelpers`) was **superseded 11 days later** by `49e05110` ("fail closed on hosted API access"), which deleted the break-glass mechanism entirely and made the bootstrap token **local-only** at both the plug (`api_auth.ex`) and the authorization layer (`api_helpers.ex`). This review evaluates the _current_ main state, not the intermediate design. `docs/api-reference.md:38-40` correctly documents the final behavior.

**Verified healthy:**

- Targeted tests pass: 51/51 across `break_glass_test.exs`, `plugs/api_auth_test.exs`, `cloud/workspace/key_registry_test.exs`, `controllers/oauth_login_controller_test.exs`; 568/568 across `test/controlkeel/cloud`, `test/controlkeel_web/plugs`, `test/controlkeel_web/controllers`; **full suite green: 2841 passed, 5 skipped, 1 excluded** (the `[error]` log lines during the run are expected fixtures — an invalid-job-config autonomy test and a `DBConnection` client exit on teardown — not failures).
- `ApiAuth` constant-time compare (`Plug.Crypto.secure_compare`) is correct; the `is_binary` guard is load-bearing (prevents an `ArgumentError` raise from `secure_compare/2` if config were ever a non-binary), and bootstrap is accepted only in `:local` mode — cloud fails closed.
- `ProtocolInterop.require_workspace/1` (`protocol_interop.ex:96-108`) correctly closes the hosted nil-workspace tool-policy bypass; `ServiceAccount.workspace_id` is `validate_required`, so every legitimate hosted MCP auth context resolves an integer workspace and only malformed contexts are denied.
- OAuth email-verification guard verified end-to-end against the pinned Assent `0.3.2`: the GitHub strategy fetches `/user/emails` (default scope `read:user,user:email`) and surfaces the primary entry's `verified` flag as `"email_verified"`; Google passes the OIDC `email_verified` claim through. `truthy/1` fails closed on absent/false/string values. Email matching is case/whitespace-normalized (`accounts.ex:54-57`, `user.ex:38,45-48`), so the guard actually protects the `find_or_create_user` join.
- Key re-enrollment of a **revoked** workspace correctly returns `{:error, :revoked}` → `409 workspace_registration_revoked`; sync endpoints (`CloudWorkspaceKeyAuth`, `CloudSyncController.resolve_db_workspace_id`) re-check the registry and reject revoked keys. (The _live_-key refresh branch itself has a separate defect — see B3.)
- All files changed by these four PRs are byte-identical between `main` and `fix/security-invitation-lifecycle`, so the findings apply to both and fixes branch cleanly on top of it. (Context citations to `accounts.ex` and `data_lifecycle.ex` were taken on `fix/security-invitation-lifecycle`, which is ahead of main by the invitation-lifecycle work.)
- `mix compile` warnings present on main are pre-existing and unrelated to these four PRs.

**Mode-by-mode impact:** local mode is functionally unchanged by all four PRs (bootstrap + loopback API behavior preserved; GitHub/Google always assert email verification, so the OAuth guard never blocks a legitimate local sign-in). Cloud mode fails closed as intended everywhere except the gaps below. Self-hosted (`:self_hosted`) has one real hole — B1. One mode-independent data-integrity bug (B3) is most likely to bite cloud, because org binding is what makes controlkeel.com multi-tenant.

---

## Part A — Web service, features, UI/UX (fix now, branch on top of `fix/security-invitation-lifecycle`)

### A1 — 🔴 High (cloud-launch blocker): Workspace-key revocation is terminal but has no reachable operator surface

The PR title promises revocation "terminal **and reachable**". Terminal, yes; reachable, no:

- `KeyRegistry.revoke/1` (`key_registry.ex:97-109`) has **zero production callers** — no route, no controller action, no LiveView, no CLI dispatch. It is exercised only by its own tests.
- The only code path that deletes `workspace_keys` rows is **org deletion** (`accounts/data_lifecycle.ex:380`). There is no per-key removal path.
- `KeyRegistry.list_for_org/1` (`key_registry.ex:112-121`) also has no consumer: the org-scoped projects LiveView it was written for was deleted by `d7724962` ("remove the stale /cloud/projects and /cloud/telemetry surfaces"). No admin can even _see_ enrolled devices.
- The register endpoint's moduledoc says an operator can re-provision "by removing the row" (`key_registry.ex:74-75`) — only possible with direct DB access to the production database.

**Why it matters:** at controlkeel.com a workspace key is a long-lived credential that mints unlimited 5-minute bearer tokens forever (telemetry, sync push/pull, usage). A lost or stolen laptop, or an offboarded contractor, can only be neutralized today by deleting the entire org and all of its data. This is the operational core of the very feature PR #256 shipped, and it is the one part users cannot reach.

**Recommendation:** add an "Enrolled devices" (or "Workspace keys") section to Organization Settings: list `KeyRegistry.list_for_org(org_id)` rows (name, `workspace_id`, fingerprint prefix, `last_seen_at`) with a revoke action for org admins/owners calling `KeyRegistry.revoke/1` and confirming via the existing modal pattern (`organization_settings_live.ex` revoke-membership modal is the template). Style per `docs/ui-style-guide.md`. Also broadcast an eviction event so a revoked CLI device finds out on its next sync instead of by 404 archaeology. This is the highest-value pre-launch fix in this review.

### A2 — 🟡 Medium: `enroll/1` docstring still documents the exact behavior the PR removed

`key_registry.ex:41-51` (`@doc`) still says: _"When a row already exists for `workspace_id` … **`revoked_at` is cleared**."_ That sentence describes the self-un-revocation hole PR #256 existed to close; only the `@spec` was updated. The code at `key_registry.ex:70-77` returns `{:error, :revoked}` and the test at `key_registry_test.exs:39-52` asserts it.

**Why it matters:** this is a security-critical invariant documented backwards. The next maintainer who reads the doc against the code will "fix" one of them, and there is a real chance they fix the wrong one — silently re-opening the unauthenticated un-revocation path on controlkeel.com.

**Recommendation:** rewrite the `@doc` to state the terminal-revocation contract: live rows refresh material; revoked rows return `{:error, :revoked}`; re-provisioning is an explicit operator action (see A1 for making that action real).

### A3 — 🟡 Medium: `break_glass_test.exs` is a stale shell of the superseded design

`test/controlkeel_web/break_glass_test.exs` was partially rewritten by `49e05110` but the shell survives:

- The file and module are still named _break glass_, a mechanism that no longer exists anywhere in `lib/` or `config/`.
- `setup` (lines 13-14, 17-18) deletes `:break_glass_enabled` / `:break_glass_workspace_id` — application keys **nothing reads anymore**.
- Three of the five cloud-mode tests ("denied when enabled but not scoped", "denied for a workspace outside its break-glass scope", "a string workspace id does not enable hosted bootstrap") set those dead config keys and assert denial. They are tautological restatements of "denied by default" and actively mislead a reader into thinking break-glass config still does something.

**Why it matters:** the test file is the documentation of this security surface for the next auditor. As written it suggests a config knob that doesn't exist and hides the one behavior that does (bootstrap and `:local` credentials authorize only in `:local` mode).

**Recommendation:** rename to `hosted_api_authz_test.exs` (module `ControlKeelWeb.HostedApiAuthzTest`), drop the dead env-key deletes, collapse the three tautological tests into the "denied by default" case, and keep the local-mode and fail-closed cases.

### A4 — 🟡 Medium: Moduledocs on the register surface are stale in two places

- `KeyRegistry` moduledoc (`key_registry.ex:15-16`): "`list_for_org/1` — … (used by the org-scoped projects LiveView)" — that LiveView was deleted in `d7724962`; today nothing calls it (A1 will give it a consumer; update the doc when landing).
- `CloudWorkspaceController` moduledoc (`cloud_workspace_controller.ex:27-34`): the "Responses" list documents `201/200/400/401/409/422` but never mentions the new `409 workspace_registration_revoked` case, and line 30 still describes re-enrolment as plain idempotent refresh.

**Why it matters:** these are the docs a CLI author and an operator will read to understand re-registration after revocation; both now disagree with the wire behavior. Cheap to fix, prevents a wrong integration at launch.

**Recommendation:** update both moduledocs when shipping A1/A2 (same files, same commit is fine).

### A5 — 🟢 Low: `OAuthProviders` behaviour docs lag the #244 contract change

- `oauth_providers.ex:26-27` still says `callback/3` "returns `%{email:, name:}`" — the contract now includes `email_verified: boolean()` (the `@type claims` at lines 38-42 is correct).
- The adapter contract change is undocumented for custom adapters: `OAuthLoginController.callback/2` pattern-matches `%{email:, name:, email_verified:}` (`oauth_login_controller.ex:53`), so a third-party adapter returning a map without `email_verified` now fails closed with the generic "Authentication failed" flash. That behavior is correct, but it is invisible to anyone implementing the behaviour.

**Recommendation:** refresh the moduledoc `## API` bullet and add one sentence to the `## Adapter` section: adapters must return `email_verified`, and its absence denies sign-in (fail closed). Also add a regression test for that absence: a fake adapter returning a claims map **without** `email_verified` must be refused — today the controller's pattern match (`oauth_login_controller.ex:53`) fails and falls through to the generic `{:error, _reason}` → "Authentication failed" flash, which is correct fail-closed behavior but is currently untested and easy to break silently.

### A6 — 🟢 Low (style): formatting nit in `oauth_login_controller.ex`

`require_verified_email/2` (lines 124-125) is immediately followed by the `@doc` for `oidc_request/2` (line 126) with no blank line, leaving the OAuth guard visually fused to the unrelated OIDC section. Trivial readability fix while touching the file.

### Verified-fine (no action) — Part A

- The unverified-email UX is good: the flash names the provider and tells the user what to do (`oauth_login_controller.ex:87-95`), the OAuth session is fully cleared on refusal, and no session is established (`oauth_login_controller_test.exs` asserts this). Local mode keeps working: GitHub/Google always assert verification, and the guard only refuses on false/absent claims.
- `authorized_project_root/2`'s local-mode pinning and the cloud service-account rules in `APIHelpers` are consistent with the final (post-`49e05110`) fail-closed posture documented in `docs/api-reference.md`.

---

## Part B — CLI, API, server (follow-up; document as issues now, do not block launch on these)

### B1 — 🔴 High (self-hosted security): revoked keys are indistinguishable from unknown keys, so `AuthToken.verify` falls back to the local identity

`KeyRegistry.fetch/1` maps a **revoked** row to `{:error, :not_found}` (`key_registry.ex:87-93`), and `AuthToken.resolve_public_key/1` treats `:not_found` as "fall back to the node's own `workspace-identity.json`" (`auth_token.ex:174-175`).

- **controlkeel.com (cloud): safe.** The server's local identity file will not carry a tenant `ws_…` id, so the fallback yields `:unknown_workspace` → 401.
- **Self-hosted single-node (`:self_hosted`): hole.** The receiver and the (revoked) client can share the same local identity, so `/cloud/v1/telemetry` — the one endpoint that relies on `AuthToken.verify/1` alone — keeps accepting a revoked workspace's tokens. Revocation silently doesn't apply precisely where a registry row exists.
- **Diagnostics (all modes):** sync endpoints re-check the registry and answer `404 "workspace not enrolled on this node"` (`cloud_sync_controller.ex:121-131`, `cloud_workspace_key_auth.ex:41-45`) — a revoked device user cannot distinguish "revoked" from "never enrolled", which becomes a support ticket at launch.

**Recommendation:** stop conflating the two states — have `fetch/1` return `{:error, :revoked}` (update the three call sites and tests) or add `fetch_active/1` plus a `revoked?/1`; make `resolve_public_key/1` treat `:revoked` as denial _without_ local fallback; return `401/403 "workspace_registration_revoked"` from the sync auth plug so CLI users get an actionable error.

### B2 — 🔴 High (pre-existing, accentuated by #256): a live workspace's key can be replaced by anyone who knows the `workspace_id`

`Enrollment.verify/1` proves possession of the **supplied** key only (`enrollment.ex:33-36, 213-221`); nothing verifies it against the **currently registered** key, and `enroll/1` refreshes material on live rows (`key_registry.ex:64-68`) while the register endpoint accepts enrollment with no invite at all (`cloud_workspace_controller.ex:88-89`). The `ws_…` id appears in bearer-token claims, sync payloads, and audit records, so it must be treated as known to attackers.

**Why it matters:** PR #256's own comment worries about "a caller holding the old private key" un-revoking itself — but the live-row path has the strictly stronger problem: no old-key knowledge is required at all. Anyone who learns a tenant's `workspace_id` can re-bind that workspace to their own key and take over its cloud identity (telemetry + sync). #256 made revocation sticky without closing the takeover that makes revocation the _only_ response to it.

**Recommendation (follow-up):** for an existing live row, require the proof envelope to be countersigned by the currently registered key (proper rotation), or require a workspace-scoped credential/invite for re-registration; keep proof-of-possession-only for first enrollment. Add a regression test: register with key A → register with key B (no countersignature) → must be rejected.

### B3 — 🔴 High (pre-existing, but sits in the exact branch PR #256 rewrote): re-enrolment without an invite silently wipes the workspace's org binding

`CloudWorkspaceController.enroll/2` (`cloud_workspace_controller.ex:114-131`) always passes `org_id` and `mission_workspace_id` derived from `resolve_invite/1`, which is `nil` for any register POST without an `invite_token` — and ordinary re-runs carry no valid invite anyway, since invitations are single-use (#258): the first enrolment already consumed it. `Key.changeset/2` then `cast`s those explicit `nil`s over the existing row, and Ecto applies them as changes.

**Verified empirically on main** (pure `Key.changeset/2`, no DB): casting `%{org_id: nil, mission_workspace_id: nil, name: nil}` over a bound key yields `changes: [:name, :org_id, :mission_workspace_id, :last_seen_at]` and `Ecto.Changeset.apply_changes/1` returns `org_id: nil, mission_workspace_id: nil, name: nil`.

So the live-key refresh branch that PR #256 deliberately preserved ("Re-registration of a live key only refreshes the material", `key_registry.ex:64-68`) actually also **clears `org_id`, `mission_workspace_id`, and `name`** whenever the request omits them — which is every re-run of `controlkeel cloud connect --enroll <url>` without `--invite`.

**Why it matters:** org/project binding is the tenancy spine on controlkeel.com — it feeds `list_for_org/1`, `fetch_by_mission_workspace/1`, and sync resolution (`CloudSyncController.resolve_db_workspace_id` requires an integer `mission_workspace_id`, else `404`). A routine re-enrolment silently unbinds the device from its org, hides it from every org view, and breaks its sync — while returning `200 OK`. It also amplifies B2: the same nil-cast runs during a takeover, so a hijack swaps the key _and_ severs the victim's org binding in one request.

**Recommendation (follow-up):** apply binding updates only when the request actually carries them — omit `org_id`/`mission_workspace_id`/`name` from the changeset attrs instead of passing `nil`, so absent fields keep their stored values. Regression test: enrol with an invite → re-enrol without → org binding, mission workspace, and name must survive.

### B4 — 🟡 Medium: PR #257's "require a resolved workspace on hosted tool calls" stops at MCP; the hosted A2A path still bypasses workspace tool policy

PR #257's merge message claims to "require a resolved workspace on hosted tool calls", but the fix landed only in `authorize_hosted_tool_call` (`protocol_interop.ex:77-94`, hosted `POST /mcp`). Its sibling `authorize_a2a_tool_call` (`protocol_interop.ex:178-191`, hosted `POST /a2a` under the `:hosted_a2a` pipeline) has neither check:

- no `require_workspace/1` (the nil-workspace residual #257 closed for MCP), and
- no `Accounts.check_workspace_tool_policy/2` — which is enforced only in `stdio_authorization.ex:147` (local stdio) and `protocol_interop.ex:81` (hosted MCP). `Protocol.dispatch_tool/2` itself enforces nothing.

The A2A surface dispatches `@a2a_skill_ids` (`ck_validate`, `ck_delegate`, `ck_finding`, `ck_budget`, `ck_review_*`, `ck_context`, … — `protocol_interop.ex:45-55`) to any caller holding a valid service-account access token.

**Why it matters:** a workspace allowlist/denylist configured in org settings (`/workspaces/:id/tool-policy`) is a security control that silently does not apply to A2A — the same policy-bypass class #257 was merged to close. A workspace that denylists `ck_delegate` over MCP will still dispatch it over A2A with the same token.

**Recommendation (follow-up):** reuse the MCP chain — add `require_workspace/1` and `Accounts.check_workspace_tool_policy(workspace_id, tool_name)` to `authorize_a2a_tool_call`, plus a test asserting an A2A dispatch of a denylisted tool returns a policy denial.

### B5 — 🟡 Medium: doomed register attempts still burn single-use invites

In `CloudWorkspaceController.register/2` (`cloud_workspace_controller.ex:45-49`) the `with` chain runs `resolve_invite/1` — which **destructively consumes** the token (`accounts.ex:449-476` clears `invitation_token_hash` in a transaction) — _before_ `ensure_fingerprint_unused/1` and `enroll/2`, either of which can reject (`409` fingerprint conflict, `409` revoked). A revoked workspace re-registering with a fresh invite loses the invite and then gets 409'd.

**Why it matters:** invite tokens are the scarce, human-issued resource; silently consuming one on a request that was never going to succeed is a footgun operators will hit exactly when re-provisioning after a revocation (i.e., during an incident).

**Recommendation:** run the non-destructive checks first (proof, revoked-status, fingerprint), then consume the invite and enroll in a single `Repo.transaction` so consumption can't succeed without enrollment.

### B6 — 🟢 Low: fingerprint race answers 422 instead of 409

`ensure_fingerprint_unused/1` (`cloud_workspace_controller.ex:104-112`) is check-then-act; two concurrent registrations with the same key hit the `unique_constraint(:fingerprint)` (`key.ex:45`) and surface as generic `422 persistence_failed` instead of the intended `409 fingerprint_belongs_to_other_workspace`. Cosmetic; map that constraint's message to the conflict response.

### B7 — 🟢 Low (optional cleanup): duplicate workspace lookup in the register path

`CloudWorkspaceController.enroll/2` (`cloud_workspace_controller.ex:114-116`) does its own `Repo.get_by(Key, workspace_id: …)` purely to pick `200` vs `201`, then `KeyRegistry.enroll/1` repeats the lookup. Have `enroll/1` return `{key, :created | :refreshed}` or accept the pre-computed status to collapse this to one query (also removes a benign insert-status race between the two reads).

### B8 — 🟢 Low (CLI): the new `409 workspace_registration_revoked` reaches operators as raw `inspect`

PR #256 introduced a purpose-built error code, but the CLI's `post_enrollment/2` renders every non-2xx register response as `"server returned #{status}: #{inspect(body)}"` (`cli.ex:279`), so the first signal a user gets that their device key was revoked is `server returned 409: %{"error" => "workspace_registration_revoked"}`. Discoverable, but not actionable — and it is exactly the error that surfaces during an incident re-provision.

**Recommendation:** map `workspace_registration_revoked` (and `fingerprint_belongs_to_other_workspace`) in `enroll_remote/3` to plain language — e.g. "this device's registration was revoked by an org admin; ask them to issue a new enrolment invite". CLI-side, so Part B.

### Verified-fine (no action) — Part B

- `ApiAuth` (`api_auth.ex:34-51`): bootstrap accepted only when `Mode.current() == :local` **and** the token matches constant-time; in cloud mode a `CONTROLKEEL_API_TOKEN` is inert (falls through to service-account auth) and no-token requests 401 — matches the updated API docs. The explicit `byte_size/1` pre-check in `token_matches?/2` (lines 66-69) is redundant with `secure_compare/2`'s internal length check, but harmless and conventional — keep it.
- `require_workspace/1` + `audit_denial_token/1` interplay: unresolved workspaces deny with `policy:workspace_unresolved`, which lands in the MCP audit log correctly.
- The OIDC tenant path (`default_adapter.ex:83-106`) independently fail-closes on unverified emails, consistent with #244's rule.

---

## Summary

**Fix first (Part A, branch on top of `fix/security-invitation-lifecycle`):**

1. **A1 — build the revocation/list UI.** Ship an Organization Settings "Enrolled devices" section wired to `list_for_org/1` + `revoke/1`. Without it, PR #256 gives controlkeel.com a revocation mechanism no human can operate, and a lost laptop key is valid until the org is deleted.
2. **A2 — correct the `enroll/1` docstring.** It documents the removed `revoked_at`-clearing behavior as current; a security invariant documented backwards will eventually be "fixed" backwards.
3. **A3 + A4 — delete the stale break-glass test shell and refresh the two moduledocs.** Small, mechanical, and removes the misleading residue of the superseded design before external reviewers see it.

**Optional (nice-to-have, fold into the same PR):** A5 (behaviour doc + fail-closed test for `email_verified`), A6 (blank line), B7 (single lookup in register), B6 (fingerprint constraint → 409).

**Follow-up issues (Part B, separate branch/PRs after launch):** B1 (distinguish revoked from not-found; close the self-host telemetry fallback), B2 (require authorized key rotation for live rows), and B3 (stop re-enrolment from wiping org binding — empirically verified, reachable in normal operation, and it corrupts the tenancy spine controlkeel.com runs on) are the security/data-integrity follow-ups and should be first in the Part B queue. B4 (enforce `require_workspace` + workspace tool policy on the A2A path — the residual #257 claimed to close), B5 (don't burn invites on doomed registrations), and B8 (plain-language CLI message for the new 409) are correctness/UX follow-ups; B6/B7 are cosmetic cleanups.

**Launch-readiness verdict:** the merged security changes themselves are sound and well-tested — constant-time token compare, hosted fail-closed authz, OAuth email verification, and terminal revocation all behave as designed in both local and cloud modes. The one genuine launch blocker is A1: the revocation the PR shipped cannot be exercised by any operator surface. A1–A4 are a small, low-risk PR that makes the feature operational and its documentation truthful. The re-audit added three previously unaddressed findings (B3 org-binding wipe, B4 A2A policy bypass, B8 CLI 409 rendering) plus the A5 test gap; B3 in particular deserves prompt scheduling because a normal `--enroll` re-run, not an attacker, triggers it.
