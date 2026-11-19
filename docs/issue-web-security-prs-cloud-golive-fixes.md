<!-- Suggested title: fix(web): cloud go-live residue from security PRs #257/#256/#244 — unreachable workspace-key revocation, stale break-glass docs/tests -->
<!-- Suggested labels: security, web, cloud-launch-blocker -->
<!-- Suggested base branch: fix/security-invitation-lifecycle (all findings re-verified valid at ee281096) -->
<!-- Companion issue: CLI/API/server follow-up tracked separately (docs/issue-cli-api-security-prs-cloud-golive-followup.md) -->

# fix(web): cloud go-live residue from security PRs #257/#256/#244 — unreachable workspace-key revocation, stale break-glass docs/tests

## Context

Four security branches merged into main on Nov 3 ahead of the controlkeel.com launch:

| PR   | Branch                               | Merge      | What it shipped                                                                                                                      |
| ---- | ------------------------------------ | ---------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| #257 | `security/hosted-authz-fails-closed` | `bbca3ed6` | break-glass bootstrap (later superseded by `49e05110`, which made bootstrap local-only), hosted nil-workspace tool-policy bypass fix |
| #256 | `security/cloud-key-revocation`      | `0f0fd2d2` | terminal workspace-key revocation (`409 workspace_registration_revoked`)                                                             |
| #244 | `security/oauth-email-verification`  | `7c5bfe9f` | refuse OAuth sign-in on an unverified provider email                                                                                 |
| #238 | `security/api-auth-constant-time`    | `8ee35a22` | constant-time bootstrap token compare                                                                                                |

The security behavior of all four is sound and well-tested (full suite green: 2841 passed, 5 skipped, 1 excluded). What this issue tracks is the **web-surface residue**: PR #256's revocation has no operator UI at all, and the docs/tests around the register/OAuth surfaces still describe superseded behavior. Full review: `pr-238-244-256-257-cloud-golive-review.md`.

Scope of this issue: **web service, features, and UI/UX only** — Organization Settings UI, moduledocs/user-facing docs, and web test hygiene. CLI/API/server defects (org-binding wipe, revoked≡not-found fallback, A2A tool-policy bypass, invite-burn ordering) are deliberately out of scope here — web/cloud remain independent of CLI feature replication; those are tracked in the companion follow-up issue. This issue is the fix-now set before controlkeel.com goes live, branched on top of `fix/security-invitation-lifecycle`.

All findings re-verified valid on `fix/security-invitation-lifecycle` @ `ee281096`; line references below match that branch.

## Tasks

### A1 — Workspace-key revocation is terminal but has no reachable operator surface — 🔴 High (cloud-launch blocker)

Evidence:

- `lib/controlkeel/cloud/workspace/key_registry.ex:97-109` — `revoke/1` has **zero production callers**: no route, no controller action, no LiveView, no CLI dispatch. It is exercised only by its own tests.
- The only code path that deletes `workspace_keys` rows is org deletion (`lib/controlkeel/accounts/data_lifecycle.ex:380`). There is no per-key removal path.
- `KeyRegistry.list_for_org/1` (`key_registry.ex:112-121`) has no consumer either — the org-scoped projects LiveView it was written for was deleted by `d7724962` ("remove the stale /cloud/projects and /cloud/telemetry surfaces"). No admin can even _see_ enrolled devices.
- The register endpoint's moduledoc says an operator re-provisions "by removing the row" (`key_registry.ex:74-75`) — only possible with direct DB access to the production database.

PR #256's own title promises revocation "terminal **and reachable**". Terminal, yes; reachable, no.

Expected: an org admin can see the devices enrolled against their org and revoke a lost/stolen laptop's key from the web UI, with confirmation.

Actual: at controlkeel.com a workspace key is a long-lived credential that mints unlimited 5-minute bearer tokens forever (telemetry, sync push/pull, usage). A lost laptop, or an offboarded contractor, can only be neutralized today by deleting the **entire org and all of its data**. This is the operational core of the very feature PR #256 shipped, and it is the one part users cannot reach.

Fix: add an "Enrolled devices" (or "Workspace keys") section to Organization Settings:

- list `KeyRegistry.list_for_org(org_id)` rows (name, `workspace_id`, fingerprint prefix, `last_seen_at`);
- revoke action for org admins/owners calling `KeyRegistry.revoke/1`, confirmed via the existing modal pattern (`organization_settings_live.ex` revoke-membership modal is the template);
- style per `docs/ui-style-guide.md`;
- broadcast an eviction event so a revoked CLI device finds out on its next sync instead of by 404 archaeology (the companion issue covers making that error actionable CLI-side).

Note for the listing: `list_for_org/1` filters `is_nil(revoked_at)` — decide explicitly whether the UI should also show recently revoked rows (audit value) via a second query or a parameter. This is the highest-value pre-launch fix in this issue.

### A2 — `enroll/1` docstring still documents the exact behavior PR #256 removed — 🟡 Medium

Evidence: `lib/controlkeel/cloud/workspace/key_registry.ex:41-51` (`@doc`) still says: "When a row already exists for `workspace_id` … **`revoked_at` is cleared**." That sentence describes the self-un-revocation hole PR #256 existed to close; only the `@spec` (line 52-53) was updated. The code at `key_registry.ex:70-77` returns `{:error, :revoked}`, and `test/controlkeel/cloud/workspace/key_registry_test.exs:39-52` asserts it.

Expected: the doc states the terminal-revocation contract — live rows refresh material; revoked rows return `{:error, :revoked}`; re-provisioning is an explicit operator action.

Actual: a security-critical invariant is documented backwards. The next maintainer reading doc-vs-code will "fix" one of them, and there is a real chance they fix the wrong one — silently re-opening the unauthenticated un-revocation path on controlkeel.com.

Fix: rewrite the `@doc` as above (pair it with A1 so the "explicit operator action" it references actually exists).

### A3 — `break_glass_test.exs` is a stale shell of the superseded design — 🟡 Medium

Evidence: `test/controlkeel_web/break_glass_test.exs` was partially rewritten by `49e05110` but the shell survives:

- the file and module are still named _break glass_ — a mechanism that no longer exists anywhere in `lib/` or `config/`;
- `setup` (lines 13-14, 17-18) deletes `:break_glass_enabled` / `:break_glass_workspace_id` — application keys **nothing reads anymore**;
- three of the five cloud-mode tests (lines 35-64: "denied when enabled but not scoped", "denied for a workspace outside its break-glass scope", "a string workspace id does not enable hosted bootstrap") set those dead config keys and assert denial. They are tautological restatements of "denied by default" and actively mislead a reader into thinking break-glass config still does something.

Expected: the test file documents the behavior that exists — bootstrap and `:local` credentials authorize only in `:local` mode; cloud fails closed.

Actual: the tests suggest a config knob that doesn't exist and hide the one behavior that does. This file is the documentation of this security surface for the next auditor.

Fix: rename to `hosted_api_authz_test.exs` (module `ControlKeelWeb.HostedApiAuthzTest`), drop the dead env-key deletes, collapse the three tautological tests into the "denied by default" case, keep the local-mode and fail-closed cases.

### A4 — Moduledocs on the register surface are stale in two places — 🟡 Medium

Evidence:

- `key_registry.ex:15-16` — "`list_for_org/1` — … (used by the org-scoped projects LiveView)"; that LiveView was deleted in `d7724962`. Today nothing calls it (A1 will give it a consumer — update the doc when landing).
- `lib/controlkeel_web/controllers/cloud_workspace_controller.ex:27-34` — the "Responses" list documents `201/200/400/401/409/422` but never mentions the new `409 workspace_registration_revoked` case, and line 30 still describes re-enrolment as a plain idempotent refresh.

Expected: the docs a CLI author and an operator read to understand re-registration after revocation match the wire behavior.

Actual: both disagree with it — a wrong integration at launch is the likely outcome.

Fix: update both moduledocs when shipping A1/A2 (same files, same commit is fine).

### A5 — `OAuthProviders` behaviour docs lag the #244 contract change, and the fail-closed path is untested — 🟢 Low

Evidence:

- `lib/controlkeel/accounts/oauth_providers.ex:26-27` still says `callback/3` "returns `%{email:, name:}`" — the contract now includes `email_verified: boolean()` (the `@type claims` at lines 38-42 is correct).
- The adapter contract change is undocumented for custom adapters: `OAuthLoginController.callback/2` pattern-matches `%{email:, name:, email_verified:}` (`lib/controlkeel_web/controllers/oauth_login_controller.ex:53`), so an adapter returning a map without `email_verified` fails closed with the generic "Authentication failed" flash. Correct behavior, but invisible to anyone implementing the behaviour — and no test covers it.

Expected: the behaviour doc states the contract; a regression test pins the fail-closed path.

Actual: an adapter author gets a silent generic failure, and the absence-key path can be broken without any test turning red.

Fix: refresh the moduledoc `## API` bullet; add one sentence to `## Adapter` ("adapters must return `email_verified`, and its absence denies sign-in — fail closed"); add a test where the fake adapter returns a claims map **without** `email_verified` and assert refusal (redirect to `/auth/login`, no session established).

### A6 — Formatting nit in `oauth_login_controller.ex` — 🟢 Low (style)

Evidence: `require_verified_email/2` (lines 124-125) is immediately followed by the `@doc` for `oidc_request/2` (line 126) with no blank line, leaving the OAuth guard visually fused to the unrelated OIDC section.

Fix: insert the blank line while touching the file for A5.

## Acceptance criteria

- [ ] A1: Organization Settings lists enrolled devices (`list_for_org`) with name/workspace-id/fingerprint/last-seen; org admins can revoke with confirmation; revocation takes effect on the device's next sync (eviction broadcast); covered by a LiveView test
- [ ] A2: `enroll/1` `@doc` describes the terminal-revocation contract and no longer claims `revoked_at` is cleared
- [ ] A3: `break_glass_test.exs` renamed and stripped of dead break-glass config; behavior assertions unchanged (cloud denied, local allowed, fail-closed)
- [ ] A4: both moduledocs match the wire behavior (409 revoked documented; deleted-LiveView reference removed)
- [ ] A5: `OAuthProviders` docs state the `email_verified` contract; fail-closed test for a claims map without the key added
- [ ] A6: blank line applied
- [ ] Local mode: no behavior change — this issue adds UI/docs/tests only; the OAuth sign-in flow, API auth, and register endpoint behave exactly as today

## Mode impact

- Cloud (controlkeel.com): unblocks the operational story of PR #256 — admins can actually revoke a lost device key instead of deleting the org (A1); docs/tests no longer describe superseded security mechanisms to external reviewers (A2–A5)
- Local/self-hosted: unaffected functionally — local single-user deployments never enroll into the cloud key registry; all changes are additive UI/doc/test work
