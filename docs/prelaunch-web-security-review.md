# Pre-launch web security review — PRs #242, #245, #253, #255

**Branch reviewed:** `fix/web-security-followup` (HEAD `a31beacf`, in sync with origin)

**Scope:** only the changes merged from the four security branches/PRs below, evaluated as they currently stand on this branch — including regressions and interactions introduced by the branch's 48 later commits. All four PRs are ancestors of `main`, which the branch contains.

| #   | Branch                                   | PR                                                        | Merged content                                                                       |
| --- | ---------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 1   | `security/observability-tenant-scope`    | [#242](https://github.com/aryaminus/controlkeel/pull/242) | Cross-tenant scoping on observability, findings/proofs query layer, analytics funnel |
| 2   | `security/org-suspension-killswitch`     | [#245](https://github.com/aryaminus/controlkeel/pull/245) | Org suspension as browser kill switch; API authorization fails closed                |
| 3   | `security/stdio-policy-and-token-expiry` | [#253](https://github.com/aryaminus/controlkeel/pull/253) | stdio MCP tool policy + guardrails + audit; service-account token expiry             |
| 4   | `security/sa-audit-and-hygiene`          | [#255](https://github.com/aryaminus/controlkeel/pull/255) | NHI audit events from SA admin UI; session cookie encryption                         |

**Review date:** 2026-11-20 · **Target:** controlkeel.com go-live (cloud mode) while local mode continues to run against its local database.

## Verification evidence

- Targeted run of all seven test files added/touched by the four PRs: **96 passed, 0 failures** (`tenant_isolation`, `org_suspension`, `stdio_authorization`, `service_account_expiry`, `service_account_audit`, `protocol_controller`, `mcp_integration`).
- Full `mix precommit` on the branch: **2848 passed, 5 skipped, 1 excluded, CI workflow guard passed**. No test failures introduced by the merge.
- Local vs cloud mode traced for every changed gate: all `Mode.current() == :local` short-circuits confirmed (suspension, API fail-closed, stdio auth, analytics/observability scoping). Local mode behavior is preserved throughout.
- PR #255's stated telemetry operator gate (#246) is **not a gap**: the `/cloud/telemetry` route was removed entirely (owner directive, router comment), so there is no cross-tenant console left to gate. The dropped commit `3620c319` is consistent with the current tree.
- Note: `mix precommit` runs `mix format` (rewrite, not check) and reformatted three files on this branch (`docs.html.heex`, `workspace_index_live.ex`, `observability_test.exs`) — the branch HEAD is not format-clean. Left untouched in the working tree.

---

## Part A — web service, features, and UI/UX (fix before go-live)

### A1. CRITICAL — Cross-tenant IDOR on the service-account admin page (rotate steals tokens)

- **Where:** `lib/controlkeel_web/live/workspace_service_accounts_live.ex`, `handle_event("revoke", …)` (line 76) and `handle_event("rotate", …)` (line 88). These are exactly the handlers PR #255 rewrote to route through the audited wrappers.
- **What's wrong:** both handlers parse the client-supplied `id` and act on it directly — `Platform.revoke_agent_identity(sa_id, …)` / `Platform.rotate_agent_identity_token(sa_id, …)` — with no check that the service account belongs to `socket.assigns.workspace`. LiveView event payloads are fully client-controlled, so any admin of **any** workspace can revoke or rotate **any** service account in **any** organization by sending an arbitrary `phx-value-id`. `rotate` is worse than denial: it returns the **new plaintext token**, which the page then renders into the attacker's socket (`@new_token`) — cross-tenant credential theft. Service-account IDs are sequential integers, so they are enumerable. The moduledoc claim "Cross-org access is rejected at mount" is true only for the list, not the mutations. The `WorkspaceScope` event guard only halts events when `scope_error` is already set; it does not re-scope event payloads.
- **Why it matters:** a tenant admin can take over another tenant's CI/MCP credentials and read that tenant's workspace through the API. This is the single most severe issue found and blocks cloud go-live.
- **Recommendation:** mirror the JSON API pattern already in the codebase (`ApiController.rotate_service_account/2`, `revoke_service_account/2`): fetch the account first, then authorize against **the account's own workspace** — `if account.workspace_id != socket.assigns.workspace.id -> error`. Prefer adding a shared `Platform.get_service_account_for_workspace(id, workspace_id)` (or an authorize helper) so the web and API paths cannot drift again. Add a regression test: admin of org A rotating an id belonging to org B must fail and must not emit an NHI audit row for B.

### A2. HIGH — PR #242's fail-closed conversion is incomplete: five workspace helpers still fail open

- **Where:** `lib/controlkeel/observability.ex` — these still end in `do: query` on `nil`:
  - `maybe_filter_memory_workspace/2` (line 1150)
  - `maybe_filter_import_workspace/2` (line 1467)
  - `maybe_filter_event_workspace/2` (line 1545)
  - `maybe_filter_aggregate_workspace/2` (line 1899)
  - `maybe_filter_observability_scenario_workspace/2` (line 2389)

  PR #242 converted only five other helpers (`session`, `workspace`, `invocation`, `draft`, `eval`) to the new `unfiltered/1` semantics (nil ⇒ no rows in cloud, unscoped in local). The invariant "in cloud mode an absent workspace filter means no accessible workspace, never every row" is therefore only half-enforced inside one module.

- **Concrete leaks reachable today:**
  - `workspace_overview(limit: 6)` with no `workspace_id` (cloud): `recent_sessions` is correctly emptied, but `problems_opts = [limit: 5]` then runs `problem_aggregates`, `problem_total_count`, `problem_group_count`, and `problem_examples` through `maybe_filter_aggregate_workspace(nil)` → **cross-tenant finding counts, group counts, and example findings**, and `health` is derived from them.
  - `trends([])` (cloud): `trend_sessions/findings/invocations` are emptied, but `trend_imports(nil, since)` → `maybe_filter_import_workspace(nil)` → **all tenants' import envelopes** land in `series` and `totals`.
  - Reachability (verified, not inferred): hosted dispatch passes caller arguments through unchanged — `protocol_interop.ex` (85 → 138) calls `Protocol.dispatch_tool(tool_name, arguments)` with the raw arguments after `verify_workspace_scope/2`, and `maybe_verify_workspace_argument(_sa, nil) -> :ok`. So hosted MCP `ck_observability` with `report=overview`/`trends` and no `workspace_id` (and no resolvable session) reaches `workspace_overview/1` / `trends/1` with no workspace opt, and the fail-open helpers run. The web observability LiveViews all pass an explicit `workspace_id` today, so browser exposure is limited to future callers — but the shared context is one forgotten keyword away from a leak.
- **Why it matters:** PR #242's own regression tests give false assurance — `workspace_overview with no filter yields no cross-tenant rows` asserts only `overview.runs.recent == []`, and the trends test asserts zeroed totals against a test database that contains no import rows. The fail-open paths are real but untested.
- **Recommendation:** route **every** `maybe_filter_*_workspace(query, nil)` in `observability.ex` through `unfiltered/1` (one mechanical pass; grep for `defp maybe_filter_.*_workspace(query, nil), do: query` must return nothing except genuinely non-tenant filters such as `*_session`/`*_status`/`*_since`). Extend `tenant_isolation_test.exs` so the cloud-mode assertions create foreign rows in the _imports, problems/aggregate, events, and memory_ tables, then assert empty — not just sessions.

### A3. HIGH — Suspension is not a kill switch for already-open pages

- **Where:** `Accounts.update_org/2` (line 656) performs a bare `Repo.update` with **no broadcast**; `ControlKeelWeb.LiveAuth` handles `:membership_changed`, `:sign_out_everywhere`, and `:account_disabled` — there is no org-status event.
- **What's wrong:** enforcement happens only at mount/`handle_params` boundaries (`OrgAccess.resolve`, `WorkspaceScope.assign_scope/refresh`). A member with the org's pages already mounted keeps a live process that continues to render data and handle `handle_event`s (filtering, pagination, exports) after the org is suspended. The `reject_invalid_scope` hook halts only when `scope_error` is already set. Some pages have periodic refresh loops, so they keep pulling fresh data indefinitely.
- **Why it matters:** PR #245's purpose is an incident lever ("disable an org for abuse, non-payment, offboarding"). For an abuse incident, the lever must cut off live sessions, not just new navigations.
- **Recommendation:** when `update_org` changes `status`, broadcast on a per-user topic (or an org topic subscribed by LiveAuth) and handle it in `LiveAuth.handle_membership_event/2` the same way `:account_disabled` is handled (flash + `push_navigate` out of the org). Keep the existing per-navigation gates as defence in depth.

### A4. MEDIUM-HIGH — Suspended orgs remain visible on user-scoped surfaces

- **Where:** `Accounts.list_orgs_for_user/2` (line 236) and `list_workspaces_for_user/1` filter only **membership** status, never `org.status`. `Mission.accessible_workspace_ids/1` is built on them.
- **What's wrong:** in cloud mode a suspended org's sessions still appear in `Mission.list_recent_sessions_for_user/2` — i.e., the **dashboard/home recent-session lists** — and `Analytics.funnel_summary(user: …)` still aggregates its data (helper-level: no production caller passes `:user` today, but it is the tenancy primitive for caller-scoped aggregates). The org switcher/user menu also still lists suspended orgs (clicking lands on the forbidden panel).
- **Why it matters:** the kill switch's documented contract is that a suspended org is indistinguishable from a deleted one; its data should not keep rendering on shared, user-scoped pages.
- **Recommendation:** exclude non-active orgs from `list_orgs_for_user/2` (or filter them out in `accessible_workspace_ids/1`) when `Mode.current() != :local`. Local mode has no suspension concept and must stay unfiltered. Add a test: dashboard-level `list_recent_sessions_for_user` returns no rows for a user whose only org is suspended (cloud), while local mode is unaffected.

### A5. MEDIUM — Service-account admin UI ignores the expiry PR #253 added

- **Where:** `workspace_service_accounts_live.ex` render (table at line 184) and the `rotate` handler.
- **What's wrong:**
  - No `expires_at` column and no expired styling; an expired-but-`active` credential is listed under the heading "Active service accounts" with status "active".
  - Rotate on an expired account returns `{:error, :expired}` from `Platform.rotate_service_account/2`, which the `with/else` swallows into the generic flash "Could not rotate token." — no hint that the credential is dead or how to re-arm it.
  - The API payload (`service_account_summary`) already exposes `expires_at`/`expired`/`rotated_at`; the web UI is the only surface that doesn't.
- **Why it matters:** operators at controlkeel.com manage credentials through this page; expiry is the main new lifecycle state and it is invisible, which invites surprise outages ("token stopped working") and confused support load.
- **Recommendation:** render `expires_at` (via `FormatHelpers.format_datetime/2`), show an "expired" badge when `ServiceAccount.expired?/1`, exclude expired rows from the "Active" heading or split them, and map `{:error, :expired}` to an explicit message offering a re-arm path (a follow-up expiry input on rotate, or link to an "extend expiry" action).

### A6. LOW — Dead code left behind by the PRs

- **`Accounts.org_active?/1` (PR #245, accounts.ex line 173)** is never called; `WorkspaceAccess` reimplements the check privately with a different return shape. Either delete `Accounts.org_active?/1` or have `WorkspaceAccess.org_active?/1` delegate to it (keeping the `:unbound` nil-workspace case local).
- **`Mission.list_findings_browser_sessions_for_user/2` and `Mission.list_findings_browser_sessions/0` (PR #242)** have no production callers — the global findings browser LiveView was removed (the `/findings` route now 302s to the session-scoped page). The `for_user` variant also contains a no-op, `Enum.map(&Map.put(&1, :workspace, &1.workspace))` (puts the field back onto itself). Delete both functions and the tests that only exercise them, or keep them only if a caller is landing imminently.

### A7. LOW — Doc/consistency inconsistencies around the kill switch

- `WorkspaceAccess`'s `@type denial` includes `:suspended` but the moduledoc paragraph enumerating `check/3`'s returns was never updated (still `:unbound | :forbidden | :needs_admin`).
- `WorkspaceScope.assign_scope_error/4` maps `:suspended` to `:not_found` via its catch-all, while `OrgAccess.resolve/3` maps it to `:forbidden`. Both render identical public copy (`ScopeError` shares title/message for both kinds), so there is no user-visible leak — but the asymmetry is confusing for the next reader. Prefer an explicit `:suspended -> :not_found` clause with a comment (or map both to the same kind).

### A8. OPTIONAL — Session cookie hardening and UI style consistency

- The encrypted cookie (PR #255) does not set `secure: true`. `force_ssl` with `rewrite_on: [:x_forwarded_proto]` plus HSTS already covers the practical exposure on controlkeel.com; adding `secure: true` (guarded for local dev) closes the residual case of the browser sending the cookie on a first plain-HTTP request. Low urgency, cheap. Note: adding `encryption_salt` invalidates all pre-existing session cookies on deploy — harmless pre-launch, worth a release note if any shared environments exist.
- The SA create form uses raw `<input>`/`<label>` markup instead of the imported `<.input>` component (AGENTS.md / UI style guide), and the page carries a private `format_dt/1` while `ControlKeelWeb.FormatHelpers` exists. Both predate the PRs but sit on files this review touched — worth folding into the same cleanup PR.

---

## Part B — CLI, API, and server issues (follow-up; do not block Part A)

### B1. HIGH — The JSON API does not enforce org suspension

- **Where:** `APIHelpers.authorize_workspace_for_conn/3` checks service-account workspace match and scopes, never `org.status`. `Accounts.authorize_cloud_execution/2` (which does check) is only invoked from `cloud/runtime_context.ex` — i.e. **session execution**, not REST requests.
- **What's wrong:** PR #245's summary states a suspended org's "API traffic is already refused"; that is true only for cloud executions. A suspended org's service accounts keep full read/write access to `/api/v1` (findings, proofs, exports, service-account management) via `Platform.authenticate_service_account/2`, which also ignores org status.
- **Why it matters:** for cloud operations the incident lever must cut the API tier too; today the browser is dark while automation keeps running.
- **Recommendation:** the primary chokepoint should be `ApiAuth` (right after `authenticate_service_account/2` succeeds, check `Accounts.get_org(sa.workspace_id).status` and deny in cloud/self_hosted) — that covers **every** route in one place, including endpoints that never call the authorize helper because they scope purely via `current_workspace_id/1` (e.g. `API.FindingController.list_findings/2`, which builds `browse_findings` opts without an authorize call — a helper-only fix would miss it). Optionally also return a dedicated `org_suspended` code from `authorize_workspace_for_conn`'s `:service_account` branch for the routes that do call it. Local mode is unaffected because bootstrap/local credentials already require `Mode.current() == :local`. _Consider promoting this into the pre-launch set despite the Part B label._

### B2. MEDIUM — stdio gate fails closed on schema-invalid bindings (local upgrade cliff)

- **Where:** `ControlKeel.Mcp.StdioAuthorization.authorize_tool_call/3` — `{:error, reason}` (anything except `:not_found`) → deny.
- **What's wrong:** `Binding.read/read_path` run `validate/2`, which requires integer `workspace_id` **and** `session_id`, binary `agent`, and matching root. A legacy or hand-edited `controlkeel/project.json` missing any of these yields `{:error, :invalid_binding}` → **every** stdio tool call is denied with "could not resolve this project's workspace binding". That is the documented fail-closed choice, but it is a silent cliff for local users upgrading ControlKeel: stdio MCP simply stops working until they re-run init. Additionally, `authorize_tool_call`'s `case` has no `{:ok, binding, mode}` fallback clause — it is total only because `Binding.read` validates first; a future change to validation would turn this into a `CaseClauseError` inside the gate.
- **Recommendation:** add a defensive catch-all clause (`{:ok, _binding, _mode} -> deny`) so the gate is total on its own; improve the denial message with the concrete remediation (re-run `controlkeel init` / re-attach); decide explicitly whether bindings written by older CLI versions with a different shape are auto-healed on read or stay denied (deny is the safe default). Keep deny as the default.

### B3. MEDIUM — `pop_expiry_opts/1` catch-all silently discards attributes

- **Where:** `Platform.pop_expiry_opts(_other), do: {%{}, %{}}` (added by PR #253).
- **What's wrong:** for any non-map `attrs` (e.g. a keyword-list caller), this returns an **empty attrs map**, so `create_service_account/3` proceeds to build a changeset missing `name`/`scopes` and fails with a confusing validation error instead of either working or raising. All current callers pass maps, so it is latent — but the fallback's shape is simply wrong; it should be `{%{}, other}` (or the function should reject non-maps).
- **Recommendation:** fix the catch-all to preserve `attrs`, or drop the catch-all and let a non-map raise loudly (invariant: malformed input should fail at the boundary).

### B4. LOW — Audit actor and error rendering on API paths

- `ApiController.create_service_account/rotate_service_account` derive `actor = get_in(conn.assigns, [:current_user, :email])`, which is `nil` for service-account-authenticated callers — NHI audit rows on the API path can carry no actor while the web path always does. Consider falling back to `"sa:<id/name>"` so every audited mutation names its principal.
- Expiry rejections surface as `json(%{error: inspect(reason)})` → `":expired"` with a 422. A human-readable message ("credential has expired; set a new expiry") would be kinder to API consumers.

### B5. LOW — stdio authorization cost and fail-closed blast radius

- Every stdio `tools/call` now performs: a binding file read (`Binding.read_effective`), a policy DB query, a guardrails scan, and an **audit DB write** (`AuditLog.record`). Correct per the governance goal, but it is per-call I/O on the local hot path — worth measuring against chatty agents (SQLite write per tool call) and, if it shows up, batching or async-append audit rows without weakening the deny-on-audit-failure rule (which is tested and should stay).
- The audit-storage-failure ⇒ deny rule means a full disk disables local MCP entirely. That is the intended trade-off; just ensure the denial message tells the operator to check audit storage.

### B6. VERIFIED — items that looked suspicious but are fine

- Hosted MCP `ck_observability` accepts a caller-supplied `workspace_id`, but `ProtocolInterop.verify_workspace_scope/2` validates it against the service account — cross-tenant reads are blocked (the residual issue is B1/A2's nil-scope path, above).
- `Cloud.Scope.scope_workspaces(query, [])` yields no rows (confirmed by passing tests), so the explicit `[]` clauses in `Mission.maybe_filter_finding_workspace/2` and `maybe_filter_proof_workspace/2` are redundant with `in ^[]` but harmless — optional cleanup, not a bug.
- The API `list_findings`/`list_proofs` overwrite `workspace_id` from the connection credential, and any user-supplied `workspace_ids` is ANDed (intersection), so it cannot widen access.
- PR #253's expiry model preserves backward compatibility: `expires_at = nil` never expires; rotation never silently extends a lifetime; the migration is additive/null-safe; pre-existing accounts behave exactly as before.

---

## Summary — fix first vs. optional

**Fix first (blockers for controlkeel.com go-live):**

1. **A1** — SA admin page cross-tenant revoke/rotate IDOR (rotate = token theft). CRITICAL.
2. **A2** — finish PR #242's fail-closed conversion (5 remaining `nil`-fail-open helpers in `observability.ex`) and add real cross-tenant fixture rows to the isolation tests.
3. **A3** — broadcast org-status changes and evict mounted LiveViews on suspension.
4. **A4** — exclude suspended orgs from `accessible_workspace_ids` / dashboard surfaces.
5. **B1** — org-suspension check on the JSON API tier (recommend pulling forward from Part B).

**Fix in the same pass (small, cheap, same files):**

6. **A5** — surface `expires_at`/expired state in the SA admin UI; explicit `:expired` messaging on rotate.
7. **A6/A7** — delete dead code (`Accounts.org_active?/1`, `list_findings_browser_sessions*`, the no-op `Map.put`) and align the `:suspended` docs/mappings.

**Optional / follow-up (non-blocking):**

8. **A8** — `secure: true` on the session cookie; `<.input>` + `FormatHelpers` cleanup on the SA page.
9. **B2–B5** — stdio invalid-binding remediation message + defensive clause; `pop_expiry_opts` catch-all fix; API audit actor fallback and friendlier expiry errors; stdio per-call audit performance measurement.

**Local-mode assurance:** every gate reviewed short-circuits on `Mode.current() == :local` (suspension, API fail-closed credential, stdio policy, analytics/observability scoping), and the org-suspension test explicitly pins local-mode passthrough. Nothing in this review requires changing local-mode behavior; all recommended cloud fixes must preserve those short-circuits.
