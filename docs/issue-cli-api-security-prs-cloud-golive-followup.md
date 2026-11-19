<!-- Suggested title: security(cli/api): workspace-key revocation hardening & hosted authz residuals — org-binding wipe, revoked≡not-found, A2A tool-policy bypass (PRs #256/#257 follow-up) -->
<!-- Suggested labels: security, api, follow-up -->
<!-- Suggested base branch: fix/security-invitation-lifecycle (all findings re-verified valid at ee281096) -->
<!-- Companion issue: web/UI fix-now set tracked separately (docs/issue-web-security-prs-cloud-golive-fixes.md) -->

# security(cli/api): workspace-key revocation hardening & hosted authz residuals — org-binding wipe, revoked≡not-found, A2A tool-policy bypass (PRs #256/#257 follow-up)

## Context

Four security branches merged into main on Nov 3: PR #257 (`security/hosted-authz-fails-closed`, merge `bbca3ed6`), #256 (`security/cloud-key-revocation`, `0f0fd2d2`), #244 (`security/oauth-email-verification`, `7c5bfe9f`), and #238 (`security/api-auth-constant-time`, `8ee35a22`). Their core behavior is correct and tested; the web-side residue is tracked in the companion issue. This issue covers the **API, CLI-facing, and server-side** findings: three data-integrity/security defects on the enrolment surface (one empirically verified, one the exact residual PR #257 claimed to close), a CLI error-rendering gap for the new 409, and register-path cleanup.

Cloud/web and CLI remain independent — this is not about replicating CLI features into the web. But `POST /cloud/v1/workspaces/register` is the enrolment endpoint CLI users hit against controlkeel.com from day one, so B2/B3/B5 are live on the shared cloud database at launch, not hypothetical future surface. B6/B7/B8 are cleanup.

Full review: `pr-238-244-256-257-cloud-golive-review.md`. All findings re-verified valid on `fix/security-invitation-lifecycle` @ `ee281096`; line references below match that branch.

## Tasks

### B1 — Revoked keys are indistinguishable from unknown keys, so `AuthToken.verify` falls back to the local identity — 🔴 High (self-hosted security)

Evidence:

- `lib/controlkeel/cloud/workspace/key_registry.ex:87-93` — `fetch/1` maps a **revoked** row to `{:error, :not_found}`.
- `lib/controlkeel/cloud/auth_token.ex:174-175,177-181` — `resolve_public_key/1` treats `:not_found` as "fall back to the node's own `workspace-identity.json`".

Mode analysis:

- **controlkeel.com (cloud): safe.** The server's local identity file will not carry a tenant `ws_…` id, so the fallback yields `:unknown_workspace` → 401.
- **Self-hosted single-node (`:self_hosted`): hole.** Receiver and (revoked) client can share the same local identity, so `/cloud/v1/telemetry` — the one endpoint relying on `AuthToken.verify/1` alone — keeps accepting a revoked workspace's tokens. Revocation silently doesn't apply precisely where a registry row exists.
- **Diagnostics (all modes):** sync endpoints re-check the registry and answer `404 "workspace not enrolled on this node"` (`cloud_sync_controller.ex:121-131`, `cloud_workspace_key_auth.ex:41-45`) — a revoked device user cannot distinguish "revoked" from "never enrolled".

Expected: revocation is terminal on every surface, and the error tells the operator why.

Actual: the two states are conflated, so the fallback re-admits revoked credentials on self-host and cloud users get a misleading 404 during exactly the incident the revocation feature exists for.

Fix: stop conflating the states —

- have `fetch/1` return `{:error, :revoked}` (update the three call sites and tests), or add `fetch_active/1` plus `revoked?/1`;
- make `resolve_public_key/1` treat `:revoked` as denial **without** local fallback;
- return `401/403 "workspace_registration_revoked"` from the sync auth plug so CLI users get an actionable error (the companion web issue's A1 eviction broadcast makes the device side find out too).

### B2 — A live workspace's key can be replaced by anyone who knows the `workspace_id` — 🔴 High (pre-existing, accentuated by #256)

Evidence:

- `lib/controlkeel/cloud/enrollment.ex:33-36,120-140,213-221` — `Enrollment.verify/1` proves possession of the **supplied** key only; nothing verifies it against the **currently registered** key.
- `key_registry.ex:64-68` — `enroll/1` refreshes key material on live rows.
- `cloud_workspace_controller.ex:88-89` — the register endpoint accepts enrolment with no invite at all.

The `ws_…` id appears in bearer-token claims, sync payloads, and audit records, so it must be treated as known to attackers.

Expected: replacing a registered key requires authorization from the existing key (or a credential), not just knowledge of an identifier.

Actual: anyone who learns a tenant's `workspace_id` can re-bind that workspace to their own key and take over its cloud identity (telemetry + sync). PR #256's own comment worries about "a caller holding the old private key" un-revoking itself — but the live-row path has the strictly stronger problem: no old-key knowledge is required at all. #256 made revocation sticky without closing the takeover that makes revocation the _only_ response to it. (It also severs the org binding in the same request — see B3.)

Fix: for an existing live row, require the proof envelope to be countersigned by the currently registered key (proper rotation), or require a workspace-scoped credential/invite for re-registration; keep proof-of-possession-only for first enrollment. Regression test: register with key A → register with key B (no countersignature) → must be rejected.

### B3 — Re-enrolment without an invite silently wipes the workspace's org binding — 🔴 High (pre-existing, but sits in the exact branch PR #256 rewrote)

Evidence: `cloud_workspace_controller.ex:114-131` — `enroll/2` always passes `org_id` and `mission_workspace_id` derived from `resolve_invite/1`, which is `nil` for any register POST without an `invite_token` — and ordinary re-runs carry no valid invite anyway, since invitations are single-use (#258): the first enrolment already consumed it. `Key.changeset/2` then `cast`s those explicit `nil`s over the existing row, and Ecto applies them as changes.

**Verified empirically on `ee281096`** (pure `Key.changeset/2`, no DB):

```elixir
# existing: org_id: 5, mission_workspace_id: 7, name: "laptop"
Key.changeset(existing, %{…, name: nil, org_id: nil, mission_workspace_id: nil, …})
# => changes: [:name, :org_id, :mission_workspace_id, :last_seen_at]
# apply_changes → org_id: nil, mission_workspace_id: nil, name: nil
```

So the live-key refresh branch that PR #256 deliberately preserved ("Re-registration of a live key only refreshes the material", `key_registry.ex:64-68`) actually also **clears `org_id`, `mission_workspace_id`, and `name`** whenever the request omits them — which is every re-run of `controlkeel cloud connect --enroll <url>` without `--invite`.

Expected: re-enrolment refreshes key material; absent fields keep their stored values.

Actual: a routine re-enrolment silently unbinds the device from its org, hides it from `list_for_org/1`, breaks sync (`CloudSyncController.resolve_db_workspace_id` requires an integer `mission_workspace_id`, else `404`) — while returning `200 OK`. It also amplifies B2: a takeover swaps the key _and_ severs the victim's org binding in one request. Org/project binding is the tenancy spine controlkeel.com runs on.

Fix: apply binding updates only when the request actually carries them — omit `org_id`/`mission_workspace_id`/`name` from the changeset attrs instead of passing `nil`, so absent fields keep their stored values. Regression test: enrol with an invite → re-enrol without → org binding, mission workspace, and name must survive.

### B4 — PR #257's "require a resolved workspace on hosted tool calls" stops at MCP; the hosted A2A path still bypasses workspace tool policy — 🟡 Medium

Evidence:

- `lib/controlkeel/mcp/protocol_interop.ex:77-94` — the fix landed only in `authorize_hosted_tool_call` (hosted `POST /mcp`).
- `protocol_interop.ex:178-191` — its sibling `authorize_a2a_tool_call` (hosted `POST /a2a`, `:hosted_a2a` pipeline) has **neither** `require_workspace/1` **nor** `Accounts.check_workspace_tool_policy/2`.
- Policy is enforced only in `lib/controlkeel/mcp/stdio_authorization.ex:147` (local stdio) and `protocol_interop.ex:81` (hosted MCP); `Protocol.dispatch_tool/2` enforces nothing.
- The A2A surface dispatches `@a2a_skill_ids` (`ck_validate`, `ck_delegate`, `ck_finding`, `ck_budget`, `ck_review_*`, `ck_context`, … — `protocol_interop.ex:45-55`) to any caller holding a valid service-account access token.

Expected: a workspace allowlist/denylist configured in org settings (`/workspaces/:id/tool-policy`) applies to every hosted dispatch surface for those tools.

Actual: the policy silently does not apply to A2A — the same policy-bypass class #257 was merged to close. A workspace that denylists `ck_delegate` over MCP will still dispatch it over A2A with the same token.

Fix: reuse the MCP chain — add `require_workspace/1` and `Accounts.check_workspace_tool_policy(workspace_id, tool_name)` to `authorize_a2a_tool_call`, plus a test asserting an A2A dispatch of a denylisted tool returns a policy denial.

### B5 — Doomed register attempts still burn single-use invites — 🟡 Medium

Evidence: `cloud_workspace_controller.ex:45-49` — the `with` chain runs `resolve_invite/1`, which **destructively consumes** the token (`lib/controlkeel/accounts.ex:449-476` clears `invitation_token_hash` in a transaction), _before_ `ensure_fingerprint_unused/1` and `enroll/2`, either of which can reject (`409` fingerprint conflict, `409` revoked — B1's surface). A revoked workspace re-registering with a fresh invite loses the invite and then gets 409'd.

> Cross-reference: this is the same finding as B2 of the removed `issue-cli-api-invitation-lifecycle-followup.md` (dropped in `ee281096` as outdated) — the code path is unchanged, so the finding still stands.

Expected: a retryable enrolment failure does not consume a single-use credential.

Actual: invite tokens are the scarce, human-issued resource; silently consuming one on a request that was never going to succeed is a footgun operators hit exactly when re-provisioning after a revocation (i.e., during an incident).

Fix: run the non-destructive checks first (proof, revoked-status, fingerprint), then consume the invite and enroll in a single `Repo.transaction` so consumption can't succeed without enrollment.

### B6 — Fingerprint race answers 422 instead of 409 — 🟢 Low

Evidence: `ensure_fingerprint_unused/1` (`cloud_workspace_controller.ex:104-112`) is check-then-act; two concurrent registrations with the same key hit `unique_constraint(:fingerprint)` (`lib/controlkeel/cloud/workspace/key.ex:45`) and surface as generic `422 persistence_failed` instead of the intended `409 fingerprint_belongs_to_other_workspace`.

Fix: map that constraint's message to the conflict response (the changeset already carries both constraint declarations for SQLite/index-name adapters).

### B7 — Duplicate workspace lookup in the register path — 🟢 Low (optional cleanup)

Evidence: `cloud_workspace_controller.ex:114-116` — `enroll/2` does its own `Repo.get_by(Key, workspace_id: …)` purely to pick `200` vs `201`, then `KeyRegistry.enroll/1` repeats the lookup.

Fix: have `enroll/1` return `{key, :created | :refreshed}` or accept the pre-computed status to collapse this to one query (also removes a benign insert-status race between the two reads).

### B8 — The new `409 workspace_registration_revoked` reaches operators as raw `inspect` — 🟢 Low (CLI)

Evidence: PR #256 introduced a purpose-built error code, but `ControlKeel.post_enrollment/2` renders every non-2xx register response as `"server returned #{status}: #{inspect(body)}"` (`lib/controlkeel/cli.ex:279`), so the first signal a user gets that their device key was revoked is `server returned 409: %{"error" => "workspace_registration_revoked"}`.

Expected: a plain-language, actionable message — this is exactly the error that surfaces during an incident re-provision.

Actual: discoverable but not actionable; the operator must know the internal error code to know what to do.

Fix: map `workspace_registration_revoked` (and `fingerprint_belongs_to_other_workspace`) in `enroll_remote/3` to plain language — e.g. "this device's registration was revoked by an org admin; ask them to issue a new enrolment invite". No CLI feature replication involved — this is rendering an existing server response.

### Aside — `mix compile --warnings-as-errors` fails (pre-existing, not these four PRs)

Warnings in `lib/controlkeel/mcp/tools/ck_review_submit.ex:45`, `lib/controlkeel_web/controllers/oauth_login_controller.ex:132,170` (OIDC dynamic-type inference), `lib/controlkeel/cli/dispatch/providers_budget.ex:230`, `lib/controlkeel_web/live/benchmarks_live.ex:128`, `lib/controlkeel_web/controllers/api_controller.ex:615`. PR files from the four branches are otherwise warning-clean. Worth clearing before enforcing a strict CI gate at launch; can ride along with this issue or be tracked separately.

## Acceptance criteria

- [ ] B1: `fetch/1` (or a new accessor) distinguishes revoked from not-found; `AuthToken.verify` denies revoked keys without local-identity fallback on every surface; sync auth returns an actionable revoked error; tests updated
- [ ] B2: re-registration with a new key for an existing live row is rejected unless countersigned/authorized; regression test (key A → key B rejected)
- [ ] B3: re-enrolment without an invite preserves `org_id`, `mission_workspace_id`, and `name`; regression test (enrol with invite → re-enrol without → bindings survive)
- [ ] B4: A2A dispatch enforces `require_workspace` + workspace tool policy; denylisted-tool A2A test added
- [ ] B5: fingerprint conflict / revoked key does not consume the invitation; invite consumption and enrolment are transactional
- [ ] B6: fingerprint unique-constraint collision maps to 409
- [ ] B7: single workspace lookup per register request (may be folded into B3's changeset work)
- [ ] B8: CLI renders revoked/conflict register errors in plain language
- [ ] Local mode: no behavior change — enrolment against a local server, local stdio MCP, and local API auth behave as today; this issue is server/API hygiene plus one CLI message

## Mode impact

- Cloud (controlkeel.com): B2/B3 protect the live enrolment endpoint's tenancy integrity (org binding is what makes the shared database multi-tenant); B4 closes a policy bypass on a hosted dispatch surface; B5/B6/B7 harden the endpoint CLI users hit from day one; B8 makes the revocation story operable from the terminal
- Self-hosted: B1 closes the revoked-token acceptance hole on `/cloud/v1/telemetry`
- Local: unaffected — direct connections, single user, no cloud registry involved
