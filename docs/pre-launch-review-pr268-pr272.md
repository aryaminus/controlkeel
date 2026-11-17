# Pre-launch Review — PR #268 and PR #272 as merged into main

Review of the changes merged into main from:

- **PR #268** — `security/user-offboarding-and-org-bypass` (merge commit `8f2ef32f`)
- **PR #272** — `feat/unbound-workspace-guard` (merge commit `959294f3`, fixes #269)

Scope: final review before taking ControlKeel live in cloud mode at controlkeel.com. Local mode (ControlKeel installed on the user's computer with a local DB) must continue to function. Reviewing main is equivalent to reviewing `refactor/user-org-layout` (main is an ancestor of it).

All targeted tests pass on current main (18 + 32 + 382 tests, including `user_offboarding_test`, `load_current_user_disabled_test`, `cloud_execution_authz_test`, `run_cloud_agent_cli_test`, `runtime_context_test`, and the full `test/controlkeel/accounts` + `test/controlkeel/cloud` suites). The findings below are code/behavior issues, not test failures.

## What the merges did

**#268 (user offboarding):**

- `Accounts.find_or_create_user/2` now rejects disabled accounts with `{:error, :account_disabled}` (was: any existing user was returned regardless of status).
- Added `Accounts.enable_user/1` and `Accounts.user_active?/1`.
- `ControlKeelWeb.Plugs.LoadCurrentUser` resolves a disabled user's session to `current_user: nil` (mid-session revocation).
- `OAuthLoginController` handles `{:error, :account_disabled}` with a flash message and session clear.
- `Mission.Workspace` changeset gained `validate_inclusion(:status, ~w(draft active archived))`.

**#272 (fail closed on org-less workspaces):**

- `Accounts.authorize_cloud_execution/2` returns `{:error, :unbound_workspace}` for `org_id: nil` workspaces (was: `{:ok, :authorized}` unconditionally — the "local-first trust anchor").
- Added `MissionFixtures.org_bound_workspace_fixture/1` and reworked ~200 lines of cloud/CLI tests to pass `user_id`.

---

# Part A — Web service, features, UI/UX (fix before launch)

## A1 — Offboarding still has no production call site: you cannot actually disable a user from the product (High)

**What's wrong:** `Accounts.disable_user/1` and `enable_user/1` have zero call sites outside their own tests. PR #268's rationale explicitly says `disable_user/1` "had no production call site" — the PR hardened the *readers* but never added a *writer*. The only way to offboard someone today is attaching to the running node via IEx.

**Why it matters:** For controlkeel.com, this means the enforcement PR added an offboarding switch that no operator can reach. The "who still has access?" question the PR's moduledoc asks about still can't be answered through the product. Launching a multi-tenant SaaS without an offboard action is a policy/ops gap, not a style nit.

**Recommendation:** Add a disable/enable surface (org-scoped member management in `OrganizationSettingsLive` at minimum; a platform-admin surface if global offboarding is the intent), with a confirmation step, a flash, and the eviction behavior from A2.

## A2 — Disabled users are silently logged out; no eviction parity with `delete_user` (High)

**What's wrong:** When `LoadCurrentUser` hits a disabled user it assigns `current_user: nil` but (a) leaves the `current_user_id` session cookie in place, (b) shows no explanation — the user gets the generic login redirect, and only discovers *why* if they re-attempt OAuth, and (c) does not evict their currently-mounted LiveViews. Contrast with the GDPR `delete_user` path in `data_lifecycle.ex`, which explicitly does post-commit eviction via `LiveAuth` because "deletion alone leaves mounted pages live."

**Why it matters:** A disabled user's open tabs keep running until their next navigation/patch, and re-enabling the account instantly restores the old session without re-auth. It's also confusing UX — the account looks like a random logout.

**Recommendation:** On detecting an inactive user, clear the session keys and reuse the existing `delete_user` eviction broadcast pattern so mounted LiveViews drop immediately; show an "account disabled" message on the login page path.

## A3 — Invite flow duplicates `find_or_create_user` with divergent status behavior (Medium)

**What's wrong:** `organization_settings_live.ex:595` has its own private `find_or_create_user/1` that returns any user regardless of status, while `Accounts.find_or_create_user/2` (the one #268 hardened) gates on `user_active?/1`. Result: a disabled user can be invited to an org and receives an invitation token they can never redeem, because login is blocked. Also, the invite `format_error/1` catch-all does `inspect(reason)` — raw atoms can surface in the UI.

**Why it matters:** Two functions with the same name and different security semantics in one codebase is exactly the drift #268 was fixing. The "disabled user gets an unusable invite email" case will generate support confusion at launch.

**Recommendation:** Route the invite flow through `Accounts.find_or_create_user/2`, map `{:error, :account_disabled}` to a clear message ("This account is disabled and cannot be invited"), and replace the `inspect/1` fallback with a generic message.

## A4 — Workspace status validation has no data-normalization story for the shared cloud DB (Low, optional)

**What's wrong:** `validate_inclusion(:status, ~w(draft active archived))` matches the codebase pattern (org/policy_set/service_account) — good. But any legacy row with a non-canonical status will fail its next *status-changing* update with a raw changeset error in the workspace index error surface.

**Why it matters:** Low probability, but the cloud DB is shared and this is cheap to pre-empt.

**Recommendation:** Optional one-time normalization check (or a smoke query) before launch. The unchanged-field path is safe — `validate_inclusion` skips fields that aren't being changed.

---

# Part B — CLI, API, server (follow-up after launch)

## B1 — Local-mode `run cloud-agent` is functionally broken by #272; the required membership cannot exist in local mode (High — conflicts with "local mode must continue to function")

**What's wrong:** #272's comment claims "Org-less workspaces are a local-dev/test artifact," but in shipped local mode the default workspace is org-bound to a synthetic **Default Organization** created via `Accounts.create_org/1` — **with no owner membership**. Nothing in the local bootstrap (`LocalDefaults`, `LocalMigration`) ever creates a Membership, the CLI has no login/identity primitive (documented `TODO(ck-cli-auth)` in `cloud_selfhost.ex`), `controlkeel member invite` produces a *pending* membership, and there is no CLI `accept` command (`accept_invitation/2` is web-only and needs a logged-in user). So `authorize_cloud_execution` demands `user_id` + active membership that is impossible to establish locally → `run cloud-agent` now always fails with `:unauthorized`, and its error message ("Provide --user-id with an active org member") is unactionable.

**Why it matters:** Pre-#272, the documented "local-first trust anchor" authorized solo workspaces with no user — that was the working local flow (the deleted test even pinned it). #272 removed it globally with no mode gate, unlike every other gate in the codebase (e.g., `session_accessible?/2` explicitly mode-checks `Runtime.Mode.current() == :local`).

**Recommendation:** Either (a) mode-gate the trust anchor — in local mode, authorize cloud execution on the default org-bound workspace without a membership (or auto-provision a local system principal/owner membership at bootstrap), or (b) deliberately accept the break and fix the ceremony (CLI identity + accept command). Given the "local mode keeps working" constraint, (a) is the right call; at minimum the `TODO(ck-cli-auth)` and the Default Org should gain an owner membership so the story converges.

## B2 — CLI has no `:unbound_workspace` error arm; users get a misleading message (Medium)

**What's wrong:** `cli/dispatch/execution.ex` maps `:unauthorized`, `:org_suspended`, `:not_found`, and changesets — but `{:error, :unbound_workspace}` falls into the `{:error, changeset}` catch-all and prints `Failed to create package: :unbound_workspace` (via `format_changeset_errors/1`'s `inspect/1` fallback). PR #272 introduced the new atom and updated 8 test files but never touched the CLI's error mapping.

**Why it matters:** The one user-facing message a real local user will hit for this new behavior is the least helpful one.

**Recommendation:** Add an explicit arm, e.g. "Cloud execution unauthorized: this workspace has no organization. Rebind it to an org (`workspace create --org …`) and retry."

## B3 — Stale/contradictory docs, comments, and specs on the authz functions (Medium — cheap to fix, dangerous to leave)

- `Accounts.authorize_cloud_execution/2` `@doc` still says *"Solo workspaces (no org) are always authorized — the local-first trust anchor applies"* — the exact opposite of the implementation.
- The `NOTE:` comment sits directly above the fixed arm and still describes the *pre-fix* gap ("currently authorizes unconditionally here, which is a real gap").
- `@spec` omits `:unbound_workspace` — on both `authorize_cloud_execution/2` and `RuntimeContext.create_package/1`.
- `find_or_create_user/2` `@spec` says `{:error, Ecto.Changeset.t()}` but the function returns `{:error, :account_disabled}`.
- `session_authorized?/2` comment references "authorize_cloud_execution/2's permissive default" — no longer permissive.

**Why it matters:** The docstring actively instructs a future contributor to restore the vulnerability. This is the highest ratio of risk-to-effort in the whole review.

**Recommendation:** One small PR rewriting all five spots.

## B4 — Offboarding enforcement doesn't cover the non-session boundaries (Medium)

The `user_active?/1` doc mandates "Every authentication boundary MUST gate on this," but:

- `DeviceAuthController.issue_device_token/2` mints a CLI access token from `Accounts.get_user/1` with no `user_active?` check — a user disabled between browser approval and the CLI's token poll still gets a 30-day bearer token.
- `DeviceAuthController.verify_access_token/1` checks only that the user exists, not their status — and is currently **dead code** (no caller in lib or tests), so the device-flow bearer token has no server-side verification path at all.
- `authorize_cloud_execution` → `get_active_membership` checks membership status but not user status; a disabled user with an active membership passes cloud execution authz (defense-in-depth gap).

**Recommendation:** Gate token issue/verify on `user_active?/1`, decide the fate of `verify_access_token/1` (wire it up or delete it — it's residue from PR #260's device login), and add user-status to the cloud authz query. Also document explicitly that offboarding does *not* revoke service-account/workspace keys, and confirm the #256 key-revocation flow covers offboarded users' keys.

## B5 — Test hygiene residue from #272 (Low)

`test/controlkeel/cloud/runtime_context_test.exs` lines 23–24, 46–47, 59–60 contain `user_id: user.id,` twice in the same map literal. Harmless (later key wins) but it's visible AI-slop residue in the exact tests this PR is about. Also `authorize_workspace(nil, _attrs)` returning `:ok` in `runtime_context.ex:353` is a subtle fail-open shape (saved only by `RunPackage`'s required `workspace_id`) — prefer failing closed there.

---

# Summary

**Fix first (blocking for launch):**

1. **B1** — local-mode `run cloud-agent` regression: mode-gate the fail-closed authz (or provision a local principal/membership). This directly violates the "local mode keeps functioning" constraint.
2. **A1** — there is still no way to disable a user from the product; add the offboarding surface.
3. **B2 + B3** — CLI `:unbound_workspace` message and the contradictory docs/specs. Tiny, zero-risk, prevents someone re-opening the security hole via the docstring.

**Should fix in the Part A pass:**

4. **A2** — disabled-user logout UX + LiveView eviction parity with `delete_user`.

**Optional / follow-up:**

5. **A3** — deduplicate the invite-path `find_or_create_user` and its error formatting.
6. **B4** — device-token active checks + dead `verify_access_token/1`; cloud authz user-status check.
7. **A4, B5, B6** — status normalization check, duplicate test keys, nil-workspace fail-closed.

Suggested issue split: one issue each for B1, A1, A2, B2+B3 (can be one "authz docs & CLI error mapping" issue), and one cleanup issue for the optional items.
