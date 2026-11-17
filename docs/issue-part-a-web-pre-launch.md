# GitHub Issue — Part A (web service, features, UI/UX)

**Suggested title:** `web(offboarding): smooth org switch on revocation, disabled-user session/eviction UX, member-readable settings (pre-launch, Part A)`

**Suggested labels:** `bug`, `security`, `pre-launch`, `web`

**Branch base:** `refactor/user-org-layout`

---

## Context

PRs #268 (`security/user-offboarding-and-org-bypass`) and #272 (`feat/unbound-workspace-guard`) are merged to main. Full review: `docs/pre-launch-review-pr268-pr272.md`.

PR #268's stated goal was "make user offboarding actually revoke access." It hardened every *reader* of `user.status` (login boundary, session boundary) but never added a *writer* reachable from the product. This issue covers the web-side gaps that must be fixed before controlkeel.com goes live. CLI/API/server issues are tracked separately as Part B.

## Problem 1 (High): No production call site for `disable_user/1` / `enable_user/1`

**Evidence:**

```
grep -rn "disable_user\|enable_user" lib/   → only lib/controlkeel/accounts.ex (definitions + doc comment)
```

- `Accounts.disable_user/1` (lib/controlkeel/accounts.ex:97) and `enable_user/1` (accounts.ex:108) have zero call sites in lib outside their own tests.
- PR #268's own test moduledoc: "`disable_user/1` existed but had **no production call site**" — the PR fixed enforcement but not reachability.

**Expected:** an operator can offboard a user from the product.
**Actual:** the only way is attaching to the running node via IEx.

**Why it matters:** A multi-tenant SaaS cannot answer "who still has access?" if offboarding is not reachable. Blocking for cloud launch.

**Fix (revised — see "Update — requirement revision" below):**
- Account-level disable/enable is **not** an org-scoped surface. `Accounts.disable_user/1` / `enable_user/1` remain context-level functions with no product call site until a future **platform-admin** surface exists; org admins/owners must not be able to flip global account status.
- The eviction behavior from Problem 2 is implemented regardless: when an account *is* disabled (future platform-admin or support action), the user is signed out everywhere immediately and refused at login with an explanation.

## Problem 2 (High): Disabled users are silently logged out; no eviction parity with `delete_user`

**Evidence:**

- lib/controlkeel_web/plugs/load_current_user.ex:29–35 — disabled user resolves to `current_user: nil`; the `current_user_id` session key is **not** cleared and no flash/reason is set.
- lib/controlkeel/accounts/data_lifecycle.ex:122–129 — the GDPR `delete_user` path explicitly does post-commit eviction via `LiveAuth` because "deletion alone leaves mounted pages live." `disable_user` has no equivalent.

**Expected:** a disabled user loses access immediately, with mounted LiveViews dropping and an explainable login page.
**Actual:** open tabs keep running until next navigation/patch; re-enabling the account instantly restores the old session without re-auth; the user sees a generic login redirect with no explanation (the "account disabled" flash only appears if they re-attempt OAuth).

**Why it matters:** Mid-session revocation is incomplete (parity gap with `delete_user`), and the UX reads as a random logout.

**Fix:**
- When `LoadCurrentUser` detects an inactive user: clear the session keys (`:current_user_id`, `:session_last_active`).
- Reuse the `delete_user` post-commit eviction broadcast pattern so mounted LiveViews of the disabled user drop immediately.
- Show an "account disabled" message on the login path.

## Problem 3 (Medium): Invite flow duplicates `find_or_create_user` with divergent status behavior

**Evidence:**

- lib/controlkeel_web/live/organization_settings_live.ex:595–600 — private `find_or_create_user/1` returns any user regardless of status (uses `Accounts.get_user_by_email/1` directly).
- lib/controlkeel/accounts.ex:74–78 — `Accounts.find_or_create_user/2` gates on `user_active?/1` and returns `{:error, :account_disabled}`.
- organization_settings_live.ex:606 — `format_error/1` catch-all is `inspect(reason)`; raw atoms can surface in the UI.

**Expected:** one shared find-or-create-user implementation with one status policy.
**Actual:** two functions with the same name and different security semantics; a disabled user can be invited and receives an invitation token they can never redeem (login is blocked).

**Fix:**
- Route the invite flow through `Accounts.find_or_create_user/2`.
- Map `{:error, :account_disabled}` to a clear message ("This account is disabled and cannot be invited").
- Replace the `inspect/1` fallback with a generic message.

## Problem 4 (Low, optional): No normalization story for legacy `workspaces.status` in the shared cloud DB

- `validate_inclusion(:status, ~w(draft active archived))` (lib/controlkeel/mission/workspace.ex:58) matches the codebase pattern, but any legacy row with a non-canonical status fails its next status-changing update with a raw changeset error.
- Unchanged-field updates are safe (`validate_inclusion` skips fields with no change).
- Optional: one-time normalization check / smoke query before launch.

## Update — requirement revision (no org-scoped disable/enable; smooth org switch)

The original Problem 1 fix proposed wiring disable/enable into `OrganizationSettingsLive`'s members tab. That surface is **dropped**:

- Accounts are global, not org-scoped. A user may hold memberships in several organizations at once; disabling the account from one org's settings would sign them out everywhere and break organizations the acting admin has no authority over.
- Org admins/owners therefore get **no** disable/enable UI. `Accounts.disable_user/1` / `enable_user/1` stay in the `Accounts` context (exercised by tests, no UI call site) and are reserved for a future **platform-admin** surface.
- The org-scoped offboarding action remains **membership revocation**, which was already admin+ gated with last-owner protections.

New requirement — **smooth switch on revocation**: a revoked user must not dead-end on `/new/org` while they still belong to other organizations. `LiveAuth`'s revocation handler now:

- navigates to the user's first remaining organization (`/<org_slug>`, ordered by name) with the existing "Your access to this organization changed." flash when any active membership remains; and
- lands on `/new/org` with "You no longer have access to any organization." only when the revoked membership was the user's last one.

Revocation broadcasts fire post-commit, so the remaining-org lookup inside the handler already excludes the just-revoked membership.

## Update — settings route opened to every member (read-only below admin)

Follow-up requirement: `/:org_slug/settings` resolved at the `"admin"` floor, so members below admin who opened the page (or the sidebar Settings link) hit the shared access panel: *"You don't have permission to access this part of the organization."* The tabs are informational for every member — org identity, roster, policy sets — so the all-or-nothing gate read as an error instead of a role boundary. The page now:

- resolves `OrganizationSettingsLive` at the **`"viewer"` floor**: every active member can open all three tabs; non-members and suspended-org visitors still get the shared access panel;
- renders the tabs **static below admin**: invite button, role `<select>`s, revoke buttons, and "+ New policy set" are hidden; the General form's name input is disabled; the Save button is replaced by "Settings are read-only for your role."; status/budget keep their owner lock and the danger zone stays owner-only;
- keeps every mutation gated **server-side**: `save_settings`, invites, role changes, and revocation already checked `can_manage?` / `mutation_owner?`; `save_policy_set` did **not** — it relied on the admin-floor mount, so opening the page to viewers would have allowed a crafted event to create org policy sets. It now refuses below-admin callers with a flash (the security fix that fell out of this change);
- local mode is unchanged (single-user deployments stay unrestricted).

Tests: viewer opens all three tabs read-only (markup assertions), crafted `save_settings` / `save_policy_set` are refused with the org unchanged; the former "non-admin members see an access panel on settings" test now asserts the read-only page instead.

## Acceptance criteria

- [ ] There is **no** org-scoped disable/enable UI: org admins/owners cannot flip global account status from `OrganizationSettingsLive` (or anywhere else); the members tab offers invite, role changes, and revocation only.
- [ ] Revoking a membership smoothly switches the affected user to their first remaining organization (`/<org_slug>`); if none remain they land on `/new/org` — never a dead end, never a sign-out.
- [ ] Disabled users (account-level action, future platform-admin surface) still see an explanatory message, not a silent logout, and mounted LiveViews drop immediately (Problem 2 machinery stays).
- [ ] Invite flow uses the Accounts-level function and surfaces a clear error for disabled accounts; no raw atoms in UI error text.
- [ ] Every active member can open all `/:org_slug/settings` tabs; below admin they render read-only (management controls hidden, no save) and crafted mutation events (`save_settings`, `save_policy_set`) are refused server-side with the org unchanged.
- [ ] Local mode unaffected: web flows in local mode behave as before for active users.
- [ ] `mix test test/controlkeel/accounts/user_offboarding_test.exs test/controlkeel_web/load_current_user_disabled_test.exs` extended to cover the offboarding behavior; `mix precommit` clean.
