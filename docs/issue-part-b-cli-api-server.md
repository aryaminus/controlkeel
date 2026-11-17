# GitHub Issue — Part B (CLI, API, server)

**Suggested title:** `fix(cloud): local-mode cloud-agent regression + authz error mapping/docs/specs (follow-up, Part B)`

**Suggested labels:** `bug`, `cli`, `security`, `follow-up`

**Branch base:** `refactor/user-org-layout`

---

## Context

PRs #268 (`security/user-offboarding-and-org-bypass`) and #272 (`feat/unbound-workspace-guard`) are merged to main. Full review: `docs/pre-launch-review-pr268-pr272.md`.

Constraints: local mode (local DB) must continue to function; controlkeel.com uses a separate shared cloud DB. Web/cloud remain independent — this issue does not replicate CLI features to the web; it fixes CLI/API/server behavior introduced or exposed by the two merges. Part A (web) is tracked separately and is prioritized for launch.

## Problem 1 (High): Local-mode `run cloud-agent` is broken — the required membership cannot exist in local mode

**Evidence:**

- lib/controlkeel/accounts.ex:1392–1435 — `authorize_cloud_execution/2` fails closed for org-less workspaces and requires `user_id` + active membership for org-bound workspaces. **No `Runtime.Mode` check** (contrast with `session_accessible?/2` at accounts.ex:807–813, which explicitly mode-checks `Runtime.Mode.current() == :local`).
- lib/controlkeel/bootstrap/local_defaults.ex:59–67 — Default Organization is created with `Accounts.create_org/1`: **no owner membership**, ever. `LocalMigration` (lib/controlkeel/bootstrap/local_migration.ex:180–242) likewise never creates a Membership.
- lib/controlkeel/cli/dispatch/cloud_selfhost.ex:160–173 — `TODO(ck-cli-auth)`: the CLI has no login/identity primitive; `org_create` inserts an org with no owner membership.
- `controlkeel member invite` (cloud_selfhost.ex:369) creates a **pending** membership; there is no CLI `accept` command (`accept_invitation/2` is web-only and needs a logged-in user).
- lib/controlkeel/cli/dispatch/execution.ex:84–86 — error message: "Cloud execution unauthorized: workspace belongs to an org and no valid membership was found. Provide --user-id with an active org member."

**Command run:**
```
controlkeel run cloud-agent <task-id> --runtime devin     # local mode, default workspace
```

**Expected:** succeeds (pre-#272 behavior: the documented "local-first trust anchor" authorized solo workspaces with no user; the deleted test in `cloud_execution_authz_test.exs` pinned exactly this).

**Actual:** always fails `{:error, :unauthorized}`. The `--user-id` the error asks for cannot help: no Membership rows exist in the Default Org, and local mode provides no path to create one (CLI invite → pending, no CLI accept; web accept requires an OAuth login the local single-user flow doesn't guarantee).

**Why it matters:** Directly violates the "local mode keeps working" constraint. `run cloud-agent` + `RuntimeDispatcher` manual handoff is a designed local-mode feature (`runtime_dispatcher_test.exs` asserts a "clean dispatched transition in local mode").

**Fix (preferred):**
- Mode-gate the trust anchor: in local mode, authorize cloud execution on the org-bound default workspace without requiring a membership — or auto-provision a local system principal / owner membership for the Default Org at bootstrap (`LocalDefaults.ensure/0`).
- Converge the story: give the Default Org an owner membership and resolve or annotate the `TODO(ck-cli-auth)` accordingly.
- Alternative (if deliberately accepted): fix the ceremony — CLI identity (`controlkeel login`) plus a CLI `member accept` command — and update the CLI error text to describe the actual path.
- Tests: local-mode `run cloud-agent` end-to-end against the bootstrapped Default Workspace; cloud-mode fail-closed behavior unchanged (`cloud_execution_authz_test.exs` pins it).

## Problem 2 (Medium): CLI error mapping has no `:unbound_workspace` arm — misleading message

**Evidence:**

- lib/controlkeel/cli/dispatch/execution.ex:46–96 — `case RuntimeContext.create_package(attrs)` maps `:unauthorized`, `:org_suspended`, `:not_found`, and changesets. `{:error, :unbound_workspace}` (introduced by PR #272 in accounts.ex:1409) falls into the `{:error, changeset}` catch-all.
- lib/controlkeel/cli.ex:2320 — `format_changeset_errors(other), do: inspect(other)`.

**Expected:** an actionable message, e.g. "Cloud execution unauthorized: this workspace has no organization. Rebind it to an org (`workspace create --org …`) and retry."

**Actual:**
```
Failed to create package: :unbound_workspace
```

**Why it matters:** The most likely user-facing message for the new fail-closed behavior is the least helpful one; PR #272 updated 8 test files but never the CLI error mapping.

**Fix:** add an explicit arm for `{:error, :unbound_workspace}` in `execution.ex`.

## Problem 3 (Medium): Stale/contradictory docs, comments, and specs on the authz functions

**Evidence (current main):**

- accounts.ex:1380–1388 — `@doc`: *"Solo workspaces (no org) are always authorized — the local-first trust anchor applies"* — the **opposite** of the implementation (accounts.ex:1404–1409 returns `{:error, :unbound_workspace}`).
- accounts.ex:1400–1403 — `NOTE:` comment directly above the fixed arm still describes the pre-fix gap ("currently authorizes unconditionally here, which is a real gap").
- accounts.ex:1390–1391 — `@spec` omits `:unbound_workspace`.
- lib/controlkeel/cloud/runtime_context.ex:49–51 — `create_package/1` `@spec` omits `:unbound_workspace`.
- accounts.ex:65–66 — `find_or_create_user/2` `@spec` says `{:error, Ecto.Changeset.t()}` but the function returns `{:error, :account_disabled}`.
- accounts.ex:817–819 — `session_authorized?/2` comment references "authorize_cloud_execution/2's permissive default" — no longer permissive.

**Why it matters:** The `@doc` actively instructs a future contributor to restore the vulnerability #272 closed. Highest risk-to-effort ratio in the review; one small PR fixes all six spots.

## Problem 4 (Medium): Offboarding enforcement doesn't cover non-session boundaries

`user_active?/1`'s doc mandates "Every authentication boundary MUST gate on this," but:

- lib/controlkeel_web/controllers/device_auth_controller.ex:79–103 — `issue_device_token/2` mints a 30-day CLI bearer from `Accounts.get_user/1` with **no** `user_active?` check; a user disabled between browser approval and the CLI's token poll still receives a token.
- device_auth_controller.ex:119–136 — `verify_access_token/1` checks only that the user exists, not status — and is **dead code** (no caller in lib or tests; residue from PR #260's device login). The device-flow bearer token has no server-side verification path at all.
- accounts.ex:1422 — `get_active_membership/2` checks membership status but not user status; a disabled user with an active membership passes cloud execution authz (defense-in-depth gap).

**Fix:**
- Gate device-token issue/verify on `user_active?/1`; wire up or delete `verify_access_token/1`.
- Add user-status to the cloud authz query (join users or load the user row).
- Document that offboarding does not revoke service-account/workspace keys, and confirm the #256 key-revocation flow covers offboarded users' keys.

## Problem 5 (Low): Test hygiene residue from #272

- test/controlkeel/cloud/runtime_context_test.exs lines 23–24, 46–47, 59–60 — `user_id: user.id,` duplicated in the same map literal (harmless; later key wins).
- lib/controlkeel/cloud/runtime_context.ex:353 — `authorize_workspace(nil, _attrs), do: :ok` is a fail-open shape (saved only by `RunPackage`'s required `workspace_id`); prefer failing closed for a nil `workspace_id`.

## Acceptance criteria

- [ ] Local mode: `run cloud-agent` succeeds against the bootstrapped Default Workspace without manual membership ceremony; cloud-mode fail-closed behavior unchanged and still tested.
- [ ] CLI prints an actionable message for `:unbound_workspace` (and the message for `:unauthorized` is accurate for whatever local-mode resolution is chosen).
- [ ] All stale docs/specs/comments listed in Problem 3 corrected; dialyzer/spec checks clean.
- [ ] Device-token issue/verify gated on `user_active?/1`; `verify_access_token/1` either wired up or deleted.
- [ ] Duplicate test keys removed; `authorize_workspace(nil)` fails closed.
- [ ] `mix test test/controlkeel/cli test/controlkeel/cloud test/controlkeel/accounts` green; `mix precommit` clean.
