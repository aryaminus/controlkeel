# DSAR Erasure: Corruption Fixes + Web Feature Plan

Planning document for the work that follows [PR #271](https://github.com/aryaminus/controlkeel/pull/271) (`feat/user-org-deletion`, merged `c08b6e23`). Source review: the post-merge follow-up review (local `docs/followup-review.md`, not shipped).

Scope decision (agreed):

- **Keep** `lib/controlkeel/accounts/data_lifecycle.ex`. The retention contract, sole-owner guard, and `erased-user-<hash>` pseudonymization design are sound and worth preserving; the bugs are localized, not structural.
- **Do not wire a UI to the module until the data-lifecycle fixes land.** The module was dead code — wiring it first would have activated the corruption bugs (A3/A4) and the credential-revocation gap (B1) as user-triggerable problems.
- Both parts ship for cloud launch (controlkeel.com). **Follow-up (Part B) issues remain follow-ups.**
- Local mode and cloud mode both run this code against their respective databases; every fix below must hold in both. Cloud-specific items (B4) are called out explicitly.

## Delivery breakdown (branch → PR mapping)

The work grew past the original slice plan during implementation (the web surface pulled in a navigation/chrome restructure), so the branch splits into **two stacked PRs**, each in the 15–20-file review window:

| PR | Branch | Content | Files |
| --- | --- | --- | --- |
| 1 | `feat/user-org-followup` (commits 1–2: data-lifecycle + self-service account surface) | Part 1 — data-lifecycle integrity + self-service account surface | ~22 |
| 2 | `feat/settings-chrome` / `refactor/user-org-layout` (3 commits, stacked on PR 1) | Part 2 — settings navigation + shared chrome refactor | ~16 |

- `feat/user-org-followup` is the PR 1 branch; `refactor/user-org-layout` is cut on top of it and holds Part 2.
- Merge order is strict: PR 2 touches files PR 1 also modified (`layouts.ex`, `organization_layouts.ex`, `router.ex`, settings tests). Open both against `main`; PR 2's diff collapses to its own commits once PR 1 merges.

## Part dependency graph

```
Part 1  Data-lifecycle fixes + self-service account surface
   │
   └── Part 2  Settings navigation + shared chrome refactor
                │
                └── Follow-up (Part B): B2–B9 as separate issues
```

---

## Part 1 — Data-lifecycle integrity + self-service account surface

### 1.1 Corruption and security fixes (no surface change)

All changes in `lib/controlkeel/accounts/data_lifecycle.ex` plus tests in `test/controlkeel/accounts/data_lifecycle_test.exs`.

#### Fix review-event anonymization (issue A3)

**What:** `anonymize_review_events/2` matches rows where `actor_user_id == user.id OR target_user_id == user.id`, then nils **both** FKs and overwrites `actor_identifier` with the erased user's marker. The real write path sets `target_user_id: review.assigned_user_id` on every decision (`accounts.ex:1120-1140`), so erasing an assignee wipes the _decider's_ identity and re-attributes their decision to the erased user.

**Change:** two `update_all`s, each condition-scoped:

1. `where: e.actor_user_id == ^user.id` → `set: [actor_user_id: nil, actor_identifier: marker]`
2. `where: e.target_user_id == ^user.id` → `set: [target_user_id: nil]` (no `actor_identifier` touch)

**Test:** assignee erased, decider survives → decider's `actor_user_id`/`actor_identifier` intact; assignee's row survives with the marker only where the assignee was the actor.

#### Stop deleting retained review notes (issue A4)

**What:** `note: nil` in the same update destroys content the module's own contract table says to **Retain** (real decisions copy `feedback_notes` into `note`, `accounts.ex:1126, 1137`).

**Change:** drop `note: nil` from the `set:` list.

**Test:** insert a review event with `note: "ship it"`, erase the actor, assert `kept.note == "ship it"`.

#### Trusted credential creator tracking + revocation (issue B1 — pulled forward)

**What:** `revoke_credentials/1` matches `metadata["created_by_user_id"]`, a key no code path ever writes (`create_service_account/2` defaults `metadata` to `%{}`; the LiveView sends only `name`/`scopes`). Every service account minted by the erased user keeps authenticating after erasure. `metadata` is also client-castable, so it can never be trusted ownership.

**Change:**

1. Migration: add `created_by_user_id` (nullable) to `service_accounts`, set server-side at issuance in `Platform.create_service_account/2` / `provision_agent_identity/3` (from the authenticated user, not from client params).
2. `revoke_credentials/1` matches the new column.
3. Backfill plan for existing rows: derive from NHI `provisioned` events where the `actor` is an exact identity match; rows that cannot be attributed are left `nil` and listed for operator review (document in the migration comment).

**Tests:** service account created through the real path is revoked on user erase; API-created path also sets the column.

#### Record the erasure itself (issue A5)

**What:** `delete_user/1` and `delete_org/1` write no audit record of the erasure.

**Change:** inside each transaction, record an audit/NHI event (`"user_erased"` / `"org_erased"`) whose subject is the pseudonymous marker (or org id), so "who requested erasure, when" is durable.

**Test:** after erase, the erasure event exists.

### 1.2 Erasure ends sessions and broadcasts membership changes (issue A2)

**What:** `erase_user/1` bypassed `Accounts.sign_out_everywhere/1` and `broadcast_membership_change/1` (`accounts.ex:655, 660`). An erased user's open LiveViews (access checked at mount only) keep working; other members' org-membership views go stale.

**Change:**

- After `delete_user`'s transaction commits: `Accounts.sign_out_everywhere(user.id)`.
- Broadcast a membership-change event so org member lists refresh (route the `Repo.delete_all` of memberships through a context function, or broadcast manually after commit).
- Verify `on_mount`/`handle_params` re-checks on access-sensitive LiveViews (`WorkspaceServiceAccountsLive` is the known case).

**Tests:** LiveView test asserting the erased user's session dies (subsequent request signed out) and the mounted page errors out; membership list LiveView re-renders for surviving members.

### 1.3 Self-service account surface (issue A1)

**Surface decision (revised during implementation):** there is **no `/account` page and no dialog**. The account surface is the **Account tab of the org settings page** (`/:org_slug/settings?tab=account`), alongside the General / Members / Policy sets sections in the settings sidebar. Its actions post to backing controller endpoints (`AccountController`):

- `GET /me/export.json` — Art.15 JSON download.
- `POST /me/erase` — Art.17 erasure (type-to-confirm email; server re-checks).

The erasure form is a plain POST (no LiveView events), so the controller owns the redirect flow. The user menu's **Settings** entry routes to org settings. **Every member can use the Account tab regardless of role** — the page resolves at the `"viewer"` floor and the Account item is always the first section in the settings sidebar; org sections (General / Members / Policy sets) stay admin+ and a role that cannot use a requested section is pushed to `?tab=account`. **Local mode**: the tab renders a migrate-to-cloud notice (no user records exist and `/me/*` is blocked at the plug; the controller's signed-in check is the inner gate).

#### Download my data (Art.15)

- Entry point in the org settings Account tab → `DataLifecycle.export_user_data/1` → JSON download.
- Scope: only the caller's own id — no operator override.

#### Account erasure (Art.17)

- Account tab danger zone → destructive confirm (type-to-confirm email) → `POST /me/erase`.
- Sole-owner refusal: flash error with actionable copy naming the org(s) ("You are the last active owner of N. Promote another owner or delete those orgs first.") via `DataLifecycle.sole_owner_orgs/1`.
- On success: server clears the browser session (the 1.2 `sign_out_everywhere/1` broadcast handles the user's other LiveViews) and redirects to the login screen.

#### Org deletion (tenant purge)

- Org settings danger zone, **owner-only**, **cloud-only** — the danger zone is not rendered in local mode, and the `delete_org` event handler refuses there ("not available in local mode"). `DataLifecycle.delete_org/1` itself stays mode-agnostic (it runs against whichever database is configured) but local single-user deployments have no tenant-deletion UI.
- Authorization enforced server-side in the action/LiveView handler (`role == "owner"` checked against the DB, not just an `on_mount` assign).
- Destructive confirm naming the org and enumerating what is purged (workspaces, sessions, findings, proofs, cloud keys) vs. retained (other tenants' data — nothing).
- Calls `delete_org/1`.

#### Copy and UX requirements

- Every destructive page states the retention contract plainly: _your account is deleted; audit records survive with your identity replaced by a non-reversible `erased-user-…` marker; your org's governance data is untouched_.
- Follow [ui-style-guide.md](ui-style-guide.md): page titles, cards, destructive button tone, unique DOM ids, `<.input>` imports.

### Tests (Part 1)

- Controller tests (`account_controller_test.exs`): export downloads correct scoping (200 JSON attachment / 401 anonymous); erase refuses wrong email; erase refuses sole owner with the right copy (org survives); erase succeeds for a non-sole owner (user gone, session cleared, redirect to login); local mode blocks `/me/*` at the plug.
- LiveView tests: org settings Account tab renders export + erasure in cloud mode and is hidden locally (`?tab=account` falls back to General); org delete gated for non-owners (error, not silent no-op); flash + redirect on success; local mode hides the danger zone and refuses `delete_org` events.

---

## Part 2 — Settings navigation + shared chrome refactor

**What grew:** wiring the Account tab pulled the settings sidebar and the account chrome into scope, and the sidebar/header primitives were restructured while touching them. This part is intentionally separate from Part 1 so the feature PR stays reviewable; it has no behavior of its own beyond navigation and chrome.

### 2.1 Settings sidebar (grouped, icon-led, role-aware)

- Sidebar items grouped under text-only labels — **Personal** (Account, any member) and **Organization** (General / Members / Policy sets, admin+) — with `mt-3` separation; items carry hero icons (`user-circle`, `cog-6-tooth`, `users`, `shield-check`), labels do not.
- The variant replaces the header with a back row to the org overview and skips the breadcrumbs header; the user menu stays.

### 2.2 Sidebar-header menu

- Settings (→ org settings), Switch organization (hover flyout with the org list + create), and Sign out render **without mode checks**, except Sign out which is hidden in local mode (no session to end). Local mode's flyout lists the single implicit org.

### 2.3 Shared user menu (`ControlKeelWeb.UserMenu`)

- Extracted to its own component file, replacing the fork duplicated in `OrganizationLayouts` (modoc note retired).
- One trigger style: a clickable avatar circle (`role="button"`, keyboard-operable, `data-user-menu-trigger` selector for the JS wiring).
- Two states: **identity** (initial avatar; popover with name/email + Docs/GitHub/Settings) and **placeholder** (`placeholder_label` — e.g. "Local mode": muted device-icon avatar; popover shows just the label). No mode checks inside the component; callers decide.
- `sign_out` opt-in attr for cloud-only surfaces (the `/new/*` layout).

### 2.4 Layout cleanup

- The generic dashboard sidebar (`Layouts.sidebar`) and its helpers are deleted; the docs sidebar becomes the app's only sidebar, redesigned exclusively for docs (grouped nav: Docs / Introduction / Platform, icons on items, self-contained classes).
- `/device` is standalone: new `:device` centered-card layout, own `:device_auth` live_session, no app chrome. `dashboard.html.heex` and the `dashboard_header` + breadcrumb machinery are deleted with it.
- Public header drops the user menu; mode-agnostic Docs/GitHub links plus a Sign-in pill for cloud-anonymous only. Docs header gains an **Open app** button (→ `/`) and no user menu.

### Tests (Part 2)

- Settings: group order (Personal before Organization), member sees only the Personal group, settings sidebar keeps the user menu but no org switcher.
- Sidebar-header: local mode shows Settings/Switch-org/Create-org without Sign out (component + live-rendered).
- Chrome: docs sidebar groups/labels; `/device` renders standalone; new-pages cloud menu carries Sign out, local placeholder does not.

---

## Follow-up (Part B — separate issues, post-launch OK)

| Issue | Summary | Notes |
| ----- | ----- | ----- |
| B2 | NHI erasure `LIKE '%email%'` → exact-match set including `"web:"`/`"api:"` prefixed forms | Greptile's plain `==` fix is insufficient |
| B3 | Sole-owner check inside transaction + `select … for update`; single-query owner count | Invariant enforcement |
| B4 | `delete_org` purge of `workspace_keys` (by `org_id`), `cloud_mcp_tool_calls` (by enrolled ws ids); documented decision on received telemetry | **Cloud-launch blocker for the org-delete path** |
| B5 | Include exact-matched NHI events in `export_user_data/1` | Art.15 completeness |
| B6 | Destructure `identity_providers_deleted`; drop redundant `OrgIdentityProvider` delete (FK already `:delete_all`) | Trivial |
| B7 | Correct moduledoc: org delete hard-deletes `review_audit_events` via FK cascade; contract table columns not handled | Doc accuracy |
| B8 | Remove `"controlkeel"` salt fallback (fail loudly); document `secret_key_base` rotation caveat | Minor |
| B9 | Test hygiene: `@modagedoc` typo, valid `event_type`, missing coverage listed above | Shipped with Part 1 |

## Out of scope

- Retention-TTL sweeper for audit tables (deliberate non-goal of PR #271).
- Backup erasure (documented limitation; tracked separately).
- CLI/API surface for erasure — follow-up, web/cloud remain independent for now.
