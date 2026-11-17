# GitHub Issue — Part A (web service, features, UI/UX)

**Suggested title:** `web(offboarding): usable offboarding surface + disabled-user session/eviction UX (pre-launch, Part A)`

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

**Fix:**
- Add disable/enable to an admin surface — org-scoped member management in `OrganizationSettingsLive` at minimum; platform-admin surface if global offboarding is intended.
- Confirmation step, flash feedback, and the eviction behavior from Problem 2.
- Tests: disable via UI → login rejected (`{:error, :account_disabled}` path already covered by `test/controlkeel/accounts/user_offboarding_test.exs`), re-enable works.

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

## Acceptance criteria

- [ ] An operator can disable and re-enable a user from the web UI; disabled users cannot sign in again and lose access immediately (including mounted LiveViews).
- [ ] Disabled users see an explanatory message, not a silent logout.
- [ ] Invite flow uses the Accounts-level function and surfaces a clear error for disabled accounts; no raw atoms in UI error text.
- [ ] Local mode unaffected: web flows in local mode behave as before for active users.
- [ ] `mix test test/controlkeel/accounts/user_offboarding_test.exs test/controlkeel_web/load_current_user_disabled_test.exs` extended to cover the new surface; `mix precommit` clean.
