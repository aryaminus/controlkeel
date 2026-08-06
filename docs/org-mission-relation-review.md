# Review: `refactor/cloud-org-workspace-relation` vs `docs/org-mission-relation-issue.md`

## Reviewer context

- **Branch:** `refactor/cloud-org-workspace-relation`
- **Spec:** `docs/org-mission-relation-issue.md`
- **Method:** static analysis against the doc's acceptance criteria + migration policy, corroborated by a full runtime pass (`mix test` — 2145 passed, 0 failed, 1 excluded).
- **Status:** re-review after follow-up fixes to the web onboarding path and the websockex compile blocker.

---

## 1. Summary

The branch implements the core of the issue's plan and enforces the Session → Workspace → Org hierarchy at every init path. The two original blocking findings have split: **cloud-mode web onboarding is now fixed and tested**, while **`LocalMigration` still contradicts the issue's migration policy**.

What holds up:

- The Session → Workspace → Org hierarchy is **enforced** at every init path (CLI local, MCP bootstrap, cloud CLI) rather than just expressed in the schema.
- The binding file records `org_id` (local + cloud), optionally for old files.
- The default-budget concern from the issue (§4, "sharpest edge") is resolved: the default workspace uses `budget_cents: 0`, and `Budget.remaining/2` + `ratio/2` treat `0`/`nil` as _no gate_ (budget.ex:325-328), so no surprise $30 budget trips on first run.
- The local org-owner problem (issue §3a) is avoided by using `Accounts.create_org/1` (no owner) — no user-seed crash on first local init.
- The data migration is in-app (init-time from `controlkeel update`), not an Ecto migration (issue §3c).
- Workspace visibility now has a real UI surface: Org detail → Workspaces tab → `WorkspaceDetailLive` (issue §6).
- Cloud-mode onboarding now restricts the org picker to orgs where the user is owner/admin; `/organizations` still lists all the user's orgs.

**Remaining against the spec:** one blocker (`LocalMigration`), plus high/medium/low gaps for cloud-mode CLI membership checks, workspace-level budget gating, and the `--new-workspace` flag.

---

## 2. Verified good (matches the issue)

| #   | Area                                         | Evidence                                                                                                                                               |
| --- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| G1  | Hierarchy enforced at every local init path  | `Project.Local.init` / auto_bootstrap call `LocalDefaults.ensure/0` then `Mission.create_launch` with `workspace_id` (project/local.ex:70-72, 112-114) |
| G2  | Hierarchy enforced at cloud CLI init         | `Project.Cloud.init` resolves org → workspace → `workspace_id` into `create_launch` (project/cloud.ex:29-31)                                           |
| G3  | Single source of truth for defaults          | `Bootstrap.LocalDefaults` find-or-create, race-safe refetch on slug conflict, cloud-mode no-op                                                         |
| G4  | `org_id` recorded in binding (local + cloud)  | project/local.ex; project/cloud.ex                                                                                                                     |
| G5  | Old bindings without `org_id` still load     | field optional, no forced migration                                                                                                                    |
| G6  | Default budget = no gate (not $30)           | `budget_cents: 0` in local_defaults.ex:113; `Budget.ratio/2`/`remaining/2` return no-limit on `0`/`nil` (budget.ex:325-328)                            |
| G7  | Local owner problem avoided                  | `Accounts.create_org/1` (no owner) — no user-seed crash (issue §3a)                                                                                    |
| G8  | Migration is in-app, not DDL                 | `Bootstrap.LocalMigration.run/0` triggered by `controlkeel update` (issue §3c)                                                                         |
| G9  | Workspace visibility surface added           | `WorkspaceDetailLive` at `/organizations/:slug/workspaces/:id`; Workspaces tab on org detail                                                           |
| G10 | Local mode org-admin commands denied         | `@local_mode_denied_commands` guard (cli.ex:31-35) with tests                                                                                          |
| G11 | Cloud flag warning in local mode             | `maybe_warn_local_org_workspace_flags` (core.ex)                                                                                                       |
| G12 | Old sessions keep working until consolidated | evacuation happens before any workspace delete                                                                                                         |
| G13 | Duplicate project-name pre-check in place    | `OnboardingLive.validate_step(2)` calls `Mission.project_name_taken?/1` (checks session titles, case-insensitive); restored test covers it             |

---

## 3. Findings (by severity)

### 3.1 Resolved — cloud-mode web onboarding (was Blocking)

Previously the onboarding page was not mode-aware and raised a `CaseClauseError` in cloud mode. This is now fixed:

- `OnboardingLive` is mode-aware: local mode routes silently to the default workspace; cloud mode shows an org/workspace selector and gates onboarding on an owner/admin role (`:can_onboard`, `:cloud_mode`, `:org_options`, `:workspace_options`, `:selected_org_id`, `:selected_workspace_id` assigns).
- `handle_event("accept")` injects `workspace_id` via `maybe_put_workspace_id/2` before `create_launch_from_brief/2` (onboarding_live.ex:159).
- The `{:error, :workspace_not_found}` 2-tuple is now matched (onboarding_live.ex:167), removing the `CaseClauseError`.
- The cloud org picker calls `Accounts.list_orgs_for_user(user.id, "admin")`, so member/viewer orgs are excluded from onboarding but still listed on `/organizations`.
- Cloud-mode picker, no-org block, no-workspace block, and member-exclusion cases are covered by `onboarding_live_test.exs` (12 tests). Full suite: 2145 passed.

### 3.2 Blocking — `LocalMigration` intentionally deviates from the issue's migration policy

- Issue "Migration policy": "**If exactly one workspace exists**, link it to the default org and rename it … **If multiple orphan workspaces exist, leave them untouched** … Log a warning." Issue: "Existing sessions bound to orphan workspaces: **Continue to work. Their workspace retains its old name and slug.**"
- Implementation `Bootstrap.LocalMigration.consolidate/1` (local_migration.ex:172-231) instead, **regardless of orphan count**: moves **all** sessions into the default workspace, repoints session-scoped memory/analytics, then **hard-deletes** every empty non-default workspace (local_migration.ex:207-212) and every non-default org (local_migration.ex:219-224). Workspace config (agents, repos, baselines, tool policies, workspace-shaped memory) is cascade-deleted.

This contradicts the spec on two counts:
1. **Single orphan:** the issue says rename & reuse it (preserving its id/name/slug); the impl moves sessions and deletes the shell, losing the original identity.
2. **Multiple orphans:** the issue says leave untouched + warn; the impl consolidates and deletes them all.

The behavior is now **documented in the moduledoc** (local_migration.ex:7-16) as intentional ("legacy data … consolidates … sessions moved before any workspace is deleted"). So it is no longer an undocumented surprise — it is a **deliberate deviation** that still needs reconciliation with the written spec.

**Evidence:** local_migration.ex:172-231 (consolidate), 235-267 (best-effort backup), tests assert `workspaces_removed`/`Repo.aggregate(Workspace, :count) == 1`.

**Fix direction:** either (a) follow the spec — single orphan → rename in place; multiple orphans → warn and leave untouched; or (b) obtain explicit human approval for the destructive consolidate-and-delete path and update the issue's migration policy section to match, then surface the opt-out/backup clearly to the user at runtime.

### 3.3 High — Cloud-mode membership validation missing (`get_active_membership`)

- Issue: "Validate that the user has an active membership in the selected org (cloud mode only)" and acceptance: "`controlkeel init --org acme --workspace backend` rejects users without membership."
- `Project.Cloud` resolves org and workspace (`validate_targeting`/`resolve_org`/`resolve_workspace`, cloud.ex:29-31, 54, 67, 83) but never calls `Accounts.get_active_membership/2`. There is no CLI user identity/stored credential (acknowledged in `cli/cloud_selfhost.ex` TODO), so the CLI cannot know the "current user," and the acceptance criterion is unmet.

**Fix direction:** introduce minimal identity (e.g. `--user-id`/`--email` or `controlkeel whoami` seed) and enforce membership at org resolution; at minimum document the gap in the PR.

### 3.4 Medium — workspace-level budget displays but does not gate

- Issue §1: "Enable org-level and workspace-level policies (budgets …) to actually apply to sessions instead of being silently bypassed."
- `Budget` reads **session** `budget_cents`/`daily_budget_cents` only (budget.ex:67, 79-80, 99, 282-283, 312-320). The default workspace has `budget_cents: 0` (displayed in `workspace_detail_live`) but nothing maps workspace `budget_cents` to the session gate.
- Result: the per-workspace budget gate the issue intended (and the "one expensive session exhausts the budget for other projects" note, issue §4) is not enforced.

**Fix direction:** enforce workspace budget on session blocks; or explicitly document that workspace budgets are display-only today, and update `getting-started` with the "all local projects share one workspace/co-mingled budget" note (issue §4).

### 3.5 Low — `--new-workspace <name>` (issue §1.6) not implemented

- Parser adds `:org`, `:workspace` (parser.ex:17-18) but no `:new_workspace` switch, and `Cloud.init` has no create-new-workspace branch. In cloud mode there is no "create new" prompt path (only "select existing" or the "No workspaces" error).

**Fix direction:** wire `--new-workspace` into `Cloud.init` (org-with-default-workspace creation via `org create --default-workspace` is the workaround today).

---

## 4. Contrib others

- `Cloud.init` error path changed the public message format (`Cloud.error_message/1` with a generic fallback). Confirm the wording is actionable for cloud users (changelog?).
- `Project.Cloud` has **no unit/CLI test** yet. Org prompt, slug targeting, `workspace_without_org`, and not-found errors are untested.
- Boot-time `maybe_seed_local_defaults` provisions the default org/workspace before the migration runs on `update`; on a legacy single-orphan DB this creates a second default-workspace beside the orphan, and the subsequent migration deletes the orphan — net effect matches intent but the orphan's original id/name is lost (issue's single-orphan rename path is not honored — see 3.2).
- `local_mode_deny` lives in `ControlKeel.CLI.run_command` (cli.ex) but the same guard is duplicated conceptually in `organizations_live.ex` + `organization_detail_live.ex` (`handle_event("save"/"save_workspace")`) — three deny surfaces could drift.

---

## 5. Verification status

The websockex compile blocker (charlist `elixirc_paths` on Elixir 1.20) is resolved locally by patching `deps/websockex/mix.exs` to use string paths. **Full suite runs: 2145 passed, 0 failed, 1 excluded** (performance). Upstream, upgrade `websockex` (`mix deps.update websockex`) so this patch is not needed.

---

## 6. Recommendation

Actions to take before merge/release:

1. **Resolve the migration-policy conflict (3.2)** — align the consolidate path with the issue's "single-orphan rename / multiple-orphan leave-untouched + warn" policy, or get explicit human sign-off for the destructive path and update the issue's migration-policy section to match.
2. **Add the membership check (3.3)** once CLI identity exists; otherwise explicitly document the gap.
3. **Wire workspace budget to session gating (3.4)** or document that workspace budgets are display-only today; add the "one shared workspace/co-mingled budget" note to `getting-started` (issue §4).
4. Add tests for `Project.Cloud` (org/workspace targeting, flag validation).
5. Add the short Org → Workspace → Session doc page the issue's architecture audit requested (issue §"What the docs say"); `getting-started.md` is still silent on org/workspace/init.
