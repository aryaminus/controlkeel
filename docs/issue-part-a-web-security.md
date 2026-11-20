# GitHub issue draft — Part A (web service, features, UI/UX)

**Suggested title:** `web security follow-up (Part A): cross-tenant SA IDOR, incomplete fail-closed scoping, and suspension kill-switch gaps before controlkeel.com go-live`

**Suggested labels:** `security`, `web`, `bug`, `launch-blocker`

**Suggested milestone:** controlkeel.com go-live

---

## Body

Final pre-launch review of PRs [#242](https://github.com/aryaminus/controlkeel/pull/242), [#245](https://github.com/aryaminus/controlkeel/pull/245), [#253](https://github.com/aryaminus/controlkeel/pull/253), [#255](https://github.com/aryaminus/controlkeel/pull/255) as they stand on `fix/web-security-followup`. Full review: `docs/prelaunch-web-security-review.md`.

**Evidence:**
- `mix test test/controlkeel_web/tenant_isolation_test.exs test/controlkeel_web/org_suspension_test.exs test/controlkeel/mcp/stdio_authorization_test.exs test/controlkeel/platform/service_account_expiry_test.exs test/controlkeel_web/live/service_account_audit_test.exs test/controlkeel_web/controllers/protocol_controller_test.exs test/controlkeel/mcp/mcp_integration_test.exs` → `96 passed`
- `mix precommit` → `2848 passed, 5 skipped, 1 excluded`, CI workflow guard passed — the issues below are logic/design gaps, not test failures.
- Local vs cloud traced for every gate: all `Mode.current() == :local` short-circuits hold. All fixes below must preserve local-mode passthrough (local DB mode keeps functioning unchanged).

---

## A1. CRITICAL — Cross-tenant IDOR on the service-account admin page (rotate steals tokens)

- **Where:** `lib/controlkeel_web/live/workspace_service_accounts_live.ex` — `handle_event("revoke", …)` (line 76), `handle_event("rotate", …)` (line 88); the handlers PR #255 rewrote to the audited wrappers.
- **Expected:** a workspace admin can only revoke/rotate service accounts belonging to the workspace named in the page URL.
- **Actual:** both handlers parse the client-supplied `id` and call `Platform.revoke_agent_identity(sa_id, …)` / `Platform.rotate_agent_identity_token(sa_id, …)` with no workspace check. LiveView event payloads are client-controlled, so any admin of any workspace can act on any service account in any organization (`phx-value-id` is arbitrary; SA ids are sequential/enumerable). `rotate` returns the **new plaintext token**, which the page renders into the attacker's socket (`@new_token`) — cross-tenant credential theft. The moduledoc claim "Cross-org access is rejected at mount" holds only for the list, not the mutations; the `WorkspaceScope` event guard halts only when `scope_error` is already set and never re-scopes payloads.
- **Why it matters:** a tenant admin can take over another tenant's CI/MCP credentials and read that workspace through the API. Launch blocker.
- **Fix:** mirror the JSON API pattern (`ApiController.rotate_service_account/2`, `revoke_service_account/2`): fetch the account first, authorize against **the account's own workspace**. Prefer a shared `Platform.get_service_account_for_workspace/2` (or authorize helper) so web and API cannot drift again.
- **Regression test:** admin of org A sending `rotate`/`revoke` with an id from org B must fail, must not change the row, must not emit an NHI audit event, and must not display a token.

## A2. HIGH — PR #242's fail-closed conversion is incomplete: five workspace helpers still fail open

- **Where:** `lib/controlkeel/observability.ex` — `maybe_filter_memory_workspace/2` (line 1150), `maybe_filter_import_workspace/2` (line 1467), `maybe_filter_event_workspace/2` (line 1545), `maybe_filter_aggregate_workspace/2` (line 1899), `maybe_filter_observability_scenario_workspace/2` (line 2389) still end in `do: query` on `nil`.
- **Expected:** in cloud/self_hosted mode, an absent workspace filter means "no accessible workspace" → no rows everywhere in the module (the invariant PR #242 established for the five helpers it did convert: `session`, `workspace`, `invocation`, `draft`, `eval`).
- **Actual (reproduce in IEx, cloud mode, two tenants with data):**
  - `ControlKeel.Observability.workspace_overview(limit: 6)` with no `workspace_id` → `recent_sessions` correctly empty, but `problems_opts = [limit: 5]` runs `problem_aggregates`/`problem_total_count`/`problem_group_count`/`problem_examples` through `maybe_filter_aggregate_workspace(nil)` → cross-tenant finding counts, group counts, and example findings; `health` derives from them.
  - `ControlKeel.Observability.trends([])` → sessions/findings/invocations empty, but `trend_imports(nil, since)` → `maybe_filter_import_workspace(nil)` → all tenants' import envelopes in `series`/`totals`.
- **Reachability (verified, not inferred):** hosted dispatch passes caller arguments through unchanged — `protocol_interop.ex` (85 → 138) calls `Protocol.dispatch_tool(tool_name, arguments)` with the raw arguments after `verify_workspace_scope/2`, and `maybe_verify_workspace_argument(_sa, nil) -> :ok`. So hosted MCP `ck_observability` with `report=overview`/`trends` and no `workspace_id` (and no resolvable session) reaches `workspace_overview/1` / `trends/1` with no workspace opt, and the fail-open helpers run. Web observability LiveViews pass explicit `workspace_id` today, so browser exposure is limited to future callers — but the shared context is one forgotten keyword from a leak.
- **Why it matters:** PR #242's own tests give false assurance — `workspace_overview with no filter yields no cross-tenant rows` asserts only `overview.runs.recent == []`, and the trends assertion runs against a database with no import rows. Fail-open paths exist and are untested.
- **Fix:** route every `maybe_filter_*_workspace(query, nil)` through `unfiltered/1` (grep `defp maybe_filter_.*_workspace(query, nil), do: query` must return only genuinely non-tenant filters like `*_session`/`*_status`/`*_since`).
- **Regression test:** extend `tenant_isolation_test.exs` so cloud-mode assertions create **foreign rows in imports, problems/aggregate, events, and memory tables**, then assert those surfaces are empty — not just sessions.

## A3. HIGH — Suspension is not a kill switch for already-open pages

- **Where:** `Accounts.update_org/2` (line 656) does a bare `Repo.update` with no broadcast; `ControlKeelWeb.LiveAuth` handles `:membership_changed`, `:sign_out_everywhere`, `:account_disabled` — no org-status event exists.
- **Expected:** suspending an org (`status != "active"`) immediately cuts off its members' currently mounted LiveViews, per PR #245's incident-lever contract.
- **Actual:** enforcement runs only at mount/`handle_params` boundaries (`OrgAccess.resolve`, `WorkspaceScope.assign_scope/refresh`). An already-mounted page keeps rendering data and handling `handle_event`s (filtering, pagination, exports) after suspension; `reject_invalid_scope` halts only when `scope_error` is already set; pages with periodic refresh loops keep pulling fresh data indefinitely.
- **Why it matters:** for abuse/non-payment incidents the lever must cut live sessions, not only new navigations.
- **Fix:** broadcast on status change in `update_org` (per-user or org topic) and handle it in `LiveAuth.handle_membership_event/2` exactly like `:account_disabled` (flash + `push_navigate` out of the org). Keep the per-navigation gates as defence in depth.
- **Regression test:** mount a page for a member, suspend the org, assert the socket receives the eviction and navigates away.

## A4. MEDIUM-HIGH — Suspended orgs remain visible on user-scoped surfaces

- **Where:** `Accounts.list_orgs_for_user/2` (line 236), `Accounts.list_workspaces_for_user/1` — both filter only membership status, never `org.status`; `Mission.accessible_workspace_ids/1` is built on them.
- **Expected:** a suspended org is indistinguishable from a deleted one everywhere in cloud mode (PR #245 contract).
- **Actual:** `Mission.list_recent_sessions_for_user/2` (dashboard/home recent-session lists) still returns the suspended org's sessions; `Analytics.funnel_summary(user: …)` still aggregates its data (helper-level: no production caller passes `:user` today, but it is the tenancy primitive for caller-scoped aggregates); the org switcher still lists it.
- **Fix:** exclude non-active orgs from `list_orgs_for_user/2` (or in `accessible_workspace_ids/1`) when `Mode.current() != :local`; local mode must stay unfiltered.
- **Regression test:** cloud — a user whose only org is suspended gets `[]` from `list_recent_sessions_for_user`; local — unaffected.

## A5. MEDIUM — Service-account admin UI ignores the expiry PR #253 added

- **Where:** `workspace_service_accounts_live.ex` render (table at line 184) and the `rotate` handler.
- **Expected:** operators can see when a credential expires, see expired state clearly, and get an actionable error when rotating an expired credential.
- **Actual:** no `expires_at` column and no expired styling; expired-but-`active` credentials are listed under "Active service accounts" with status "active"; rotate on an expired account returns `{:error, :expired}`, which the `with/else` swallows into the generic flash "Could not rotate token."; the API payload already exposes `expires_at`/`expired`/`rotated_at` — the web UI is the only surface that doesn't.
- **Why it matters:** expiry is the main new lifecycle state and it is invisible on the page operators actually use — surprise outages and support load.
- **Fix:** render `expires_at` via `FormatHelpers.format_datetime/2`, add an expired badge (`ServiceAccount.expired?/1`), split or re-label expired rows, and map `{:error, :expired}` to an explicit message with a re-arm path.

## A6. LOW — Dead code left behind by the PRs

- `Accounts.org_active?/1` (PR #245, `accounts.ex` line 173) is never called; `WorkspaceAccess` reimplements it privately. Delete it, or have `WorkspaceAccess.org_active?/1` delegate (keeping the `:unbound` nil-workspace case local).
- `Mission.list_findings_browser_sessions_for_user/2` and `Mission.list_findings_browser_sessions/0` (PR #242) have no production callers (the global findings LiveView was removed; `/findings` 302s to the session-scoped page), and `for_user` contains a no-op `Enum.map(&Map.put(&1, :workspace, &1.workspace))`. Delete both functions and their tests, or keep only if a caller lands imminently.

## A7. LOW — Doc/consistency inconsistencies around the kill switch

- `WorkspaceAccess`'s `@type denial` includes `:suspended` but the moduledoc enumerating `check/3`'s returns was never updated (still `:unbound | :forbidden | :needs_admin`).
- `WorkspaceScope.assign_scope_error/4` maps `:suspended → :not_found` via its catch-all while `OrgAccess.resolve/3` maps it `→ :forbidden`; both render identical `ScopeError` copy (no user-visible leak), but the asymmetry confuses readers. Prefer an explicit `:suspended -> :not_found` clause with a comment, or map both to the same kind.

## A8. OPTIONAL — Session cookie hardening and UI style consistency

- Encrypted session cookie (PR #255) lacks `secure: true`; `force_ssl` + HSTS cover practical exposure on controlkeel.com — add `secure: true` (guarded for local dev) to close the first-plain-HTTP-request residual. Note in release notes: `encryption_salt` invalidates pre-existing session cookies on deploy.
- SA create form uses raw `<input>`/`<label>` instead of the shared `<.input>` component, and carries a private `format_dt/1` while `ControlKeelWeb.FormatHelpers` exists — fold into the same cleanup PR.

---

## Acceptance criteria

- [ ] A1: cross-workspace revoke/rotate from the LiveView is impossible; regression test added.
- [ ] A2: no `maybe_filter_*_workspace(query, nil), do: query` remains in `observability.ex` (except non-tenant filters); isolation tests cover imports/problems/events/memory with foreign rows present.
- [ ] A3: suspending an org evicts mounted LiveViews in real time; regression test added.
- [ ] A4: suspended orgs disappear from dashboard/session lists, funnel, and org switcher in cloud mode; local unaffected.
- [ ] A5: SA page shows expiry/expired state; `:expired` rotate produces an actionable message.
- [ ] A6/A7: dead code removed; `:suspended` docs/mappings aligned.
- [ ] A8 (optional): `secure: true` cookie; `<.input>`/`FormatHelpers` cleanup.
- [ ] `mix precommit` passes; local-mode passthrough tests still green.
