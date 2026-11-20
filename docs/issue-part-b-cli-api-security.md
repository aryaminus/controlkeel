# GitHub issue draft — Part B (CLI, API, and server)

**Suggested title:** `web security follow-up (Part B): API org-suspension enforcement, stdio binding fail-closed UX, and expiry code hardening (follow-up)`

**Suggested labels:** `security`, `api`, `cli`, `mcp`, `tech-debt`

**Note:** per launch triage this part is a **follow-up** — it does not block controlkeel.com go-live, except **B1**, which the reviewer recommends promoting into the pre-launch set (see below).

---

## Body

Follow-up from the final pre-launch review of PRs [#242](https://github.com/aryaminus/controlkeel/pull/242), [#245](https://github.com/aryaminus/controlkeel/pull/245), [#253](https://github.com/aryaminus/controlkeel/pull/253), [#255](https://github.com/aryaminus/controlkeel/pull/255) on `fix/web-security-followup`. Full review: `docs/prelaunch-web-security-review.md`. Companion Part A issue: `docs/issue-part-a-web-security.md`.

**Evidence:** `mix precommit` → `2848 passed, 5 skipped, 1 excluded`, CI workflow guard passed; the four PRs' targeted tests → `96 passed`. The items below are design/robustness gaps found by code audit, not test failures.

---

## B1. HIGH — The JSON API does not enforce org suspension *(recommend pulling forward to pre-launch)*

- **Where:** `ControlKeelWeb.APIHelpers.authorize_workspace_for_conn/3` checks service-account workspace match and scopes, never `org.status`. `Accounts.authorize_cloud_execution/2` (which does check) is only invoked from `ControlKeel.Cloud.RuntimeContext` — i.e. **session execution**, not REST requests. `Platform.authenticate_service_account/2` also ignores org status.
- **Expected (per PR #245):** disabling an org cuts off its traffic on both tiers — the PR summary states its "API traffic is already refused by `authorize_cloud_execution/2`".
- **Actual:** that claim holds only for cloud *executions*. A suspended org's service accounts retain full read/write access to `/api/v1` (findings, proofs, exports, service-account management, NHI audit listing). The browser goes dark while automation keeps running.
- **Why it matters:** the incident lever must cut the API tier too; a suspended-for-abuse tenant's CI can continue exfiltrating via API.
- **Fix:** the primary chokepoint should be `ApiAuth` — right after `authenticate_service_account/2` succeeds, check the owning org's status (`Accounts.get_org(sa.workspace_id)`) and deny in cloud/self_hosted mode. That covers **every** route in one place, including endpoints that never call the authorize helper because they scope purely via `current_workspace_id/1` (e.g. `API.FindingController.list_findings/2` builds `browse_findings` opts without an authorize call — a helper-only fix would miss it). Optionally also return a dedicated `org_suspended` code from `authorize_workspace_for_conn`'s `:service_account` branch for the routes that do call it. Local mode is unaffected — bootstrap/local credentials already require `Mode.current() == :local`, so the local-DB flow keeps functioning.
- **Regression test:** cloud — a service account whose org is suspended gets 403 (or 401, per chosen policy) on `GET /api/v1/findings` and on a mutating endpoint; local — loopback/bootstrap calls unchanged.

## B2. MEDIUM — stdio gate fails closed on schema-invalid bindings (local upgrade cliff)

- **Where:** `ControlKeel.Mcp.StdioAuthorization.authorize_tool_call/3` — any `{:error, reason}` other than `:not_found` → deny.
- **Expected:** a project that was working with stdio MCP keeps working across upgrades, or fails with an actionable remediation message; the gate is total regardless of `Binding` internals.
- **Actual:** `Binding.read/read_path` run `validate/2`, which requires integer `workspace_id` **and** `session_id`, binary `agent`, and a matching root. A legacy or hand-edited `controlkeel/project.json` missing any of these yields `{:error, :invalid_binding}` → **every** stdio tool call is denied with "could not resolve this project's workspace binding". Fail-closed is the documented choice, but this is a silent cliff for local users upgrading ControlKeel — stdio MCP simply stops until they re-run init. Separately, `authorize_tool_call`'s `case` has **no `{:ok, binding, mode}` fallback clause**: it is total only because `Binding.read` validates first, so a future validation change would raise `CaseClauseError` inside the gate.
- **Fix:** add a defensive catch-all (`{:ok, _binding, _mode} -> deny`) so the gate is total on its own; put the concrete remediation in the denial message (re-run `controlkeel init` / re-attach); decide explicitly whether bindings written by older CLI versions with a different shape are auto-healed on read or stay denied (deny is the safe default).
- **Test:** binding file present but missing `session_id` → deny with remediation text; malformed gate input never raises.

## B3. MEDIUM — `pop_expiry_opts/1` catch-all silently discards attributes

- **Where:** `ControlKeel.Platform.pop_expiry_opts(_other), do: {%{}, %{}}` (added by PR #253).
- **Expected:** a non-map `attrs` either works or fails loudly at the boundary.
- **Actual:** for any non-map input (e.g. a keyword-list caller) the function returns an **empty attrs map**, so `create_service_account/3` builds a changeset missing `name`/`scopes` and fails with a confusing validation error instead of working or raising. All current callers pass maps, so it is latent — but the fallback's shape is wrong; it should be `{%{}, other}`.
- **Fix:** preserve `attrs` in the catch-all (`{%{}, other}`), or drop the catch-all and let a non-map raise loudly. Add a unit test for a keyword-list caller.

## B4. LOW — Audit actor and error rendering on API paths

- `ApiController.create_service_account/2` and `rotate_service_account/2` derive `actor = get_in(conn.assigns, [:current_user, :email])`, which is `nil` for service-account-authenticated callers — NHI audit rows on the API path can carry no actor while the web path always does (`web:<email>`). Fall back to something like `"sa:<id>/<name>"` so every audited mutation names its principal.
- Expiry rejections surface as `json(%{error: inspect(reason)})` → `":expired"` with 422. Render a human-readable message ("credential has expired; set a new expiry") for API consumers.

## B5. LOW — stdio authorization cost and fail-closed blast radius

- Every stdio `tools/call` now performs a binding file read (`Binding.read_effective`), a policy DB query, a guardrails scan, and an **audit DB write** (`AuditLog.record`). Correct per the governance goal, but it is per-call I/O on the local hot path — measure against chatty agents (SQLite write per tool call); if it shows up, batch or async-append audit rows **without** weakening the tested deny-on-audit-failure rule.
- The audit-storage-failure ⇒ deny rule means a full disk disables local MCP entirely — intended trade-off; ensure the denial message tells the operator to check audit storage.

## B6. VERIFIED — items that looked suspicious but are fine (no action)

- Hosted MCP `ck_observability` accepts a caller-supplied `workspace_id`, but `ProtocolInterop.verify_workspace_scope/2` validates it against the service account — cross-tenant reads are blocked. The residual nil-scope path is Part A issue A2.
- `Cloud.Scope.scope_workspaces(query, [])` yields no rows (test-proven), so the explicit `[]` clauses in `Mission.maybe_filter_finding_workspace/2` and `maybe_filter_proof_workspace/2` are redundant with `in ^[]` but harmless — optional cleanup, not a bug.
- API `list_findings`/`list_proofs` overwrite `workspace_id` from the connection credential; any user-supplied `workspace_ids` is ANDed (intersection), so it cannot widen access.
- PR #253's expiry model is backward compatible: `expires_at = nil` never expires; rotation never silently extends a lifetime; the migration is additive/null-safe; pre-existing accounts behave exactly as before.

---

## Acceptance criteria

- [ ] B1: a suspended org's service accounts receive 403 on all `/api/v1` routes in cloud/self_hosted mode; local loopback/bootstrap behavior unchanged; regression tests added. *(Consider promoting to the pre-launch issue.)*
- [ ] B2: `authorize_tool_call/3` is total (defensive `{:ok, _, _}` clause) and denial messages include remediation; invalid-binding behavior covered by a test.
- [ ] B3: `pop_expiry_opts/1` preserves non-map attrs (or raises); unit test added.
- [ ] B4: API NHI events always carry an actor; expiry errors render human-readable messages.
- [ ] B5: stdio per-call audit cost measured; result recorded in the issue (no behavior change required unless measurements demand it).
- [ ] `mix precommit` passes; local mode continues to function against the local database with no changes to its short-circuits.
