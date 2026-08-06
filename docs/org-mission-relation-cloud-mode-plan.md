# Plan (new PR): Cloud-mode org/workspace selection for Session → Workspace → Org

Implements the **remaining** tasks from
[docs/org-mission-relation-issue.md](./org-mission-relation-issue.md) that are
not already satisfied by the current branch
(`refactor/cloud-org-workspace-relation`). Scoped as a **new PR** that builds on
the branch's local-mode work and completes the cloud-mode half.

## 1. Baseline — what the current branch already delivers

Verified on `refactor/cloud-org-workspace-relation` (10 commits past `b95abea`,
the 0.3.85 release):

- **1.1 / 1.2 — default org + default workspace provisioning**
  `lib/controlkeel/bootstrap/local_defaults.ex` (find-or-create, idempotent,
  race-safe, local-mode only; local config uses `budget_cents: 0`).
- **1.3 / 1.4 — sessions routed into the existing workspace**
  `Mission.create_launch/1` and `create_launch_from_brief/2` accept a
  `workspace_id` and fall back to the default workspace via
  `resolve_default_workspace/0`. `Project.Local` and CLI `setup` call
  `LocalDefaults.ensure/0` before creating sessions
  (`lib/controlkeel/mission.ex`, `lib/controlkeel/project/local.ex`,
  `lib/controlkeel/cli/dispatch/core.ex`).
- **1.5 — `org_id` in the binding**
  `Binding.write/2` writes `org_id`; `Binding.validate` treats it as optional so
  old binding files still load (`lib/controlkeel/project/binding.ex`).
- **Migration policy** — `lib/controlkeel/bootstrap/local_migration.ex` runs on
  `controlkeel update`: auto-links a single orphan workspace, warns and leaves
  multiple orphan workspaces untouched, evacuates sessions and repoints children
  before consolidation, deletes empty/non-default org shells. Idempotent, never
  blocks the caller.
- **Local-mode guards** — org-admin CLI commands (`org create/invite/members`)
  denied in local mode; web "organizations" create denied with guidance
  (`lib/controlkeel/cli.ex`, `lib/controlkeel_web/live/organizations_live.ex`).
- **Workspace visibility** — org dashboard + new `WorkspaceDetailLive` page and
  route `/organizations/:slug/workspaces/:id`, with tests.

### Branch gaps vs. the issue (this PR's scope)

The cloud-mode acceptance criteria are **not** implemented:

- [ ] `controlkeel init --org <slug> --workspace <slug>` targets a specific
      org/workspace.
- [ ] `controlkeel init` without flags prompts the operator to pick org and
      workspace (cloud).
- [ ] Passing `--org` in local mode prints a warning and uses the default anyway.
- [ ] Cloud-mode init rejects operators with no active membership in the target org.
- [ ] Web onboarding page shows an org/workspace picker in cloud mode.

**Verification caveat:** "`mix precommit` passes" cannot be confirmed on this
machine — local Elixir is 1.20.2 while the project pins `elixir: "~> 1.15"`, and
the `websockex` dep fails to compile under 1.20 (`:elixirc_paths should be a list
of string paths, got: [~c"lib"]`). This is a pre-existing toolchain mismatch
unrelated to the branch. Precommit must run in the CI image (Elixir 1.15.x); see
§5 Risks.

## 2. Architecture statement

The org → workspace → session hierarchy already exists in code. Local mode routes
everything through the single default org/workspace. Cloud mode must **select an
existing org/workspace instead of auto-creating, and validate membership** before
it. No schema changes; the work is plumbing in `init`, the web onboarding path,
and a small set of CLI switches and guard logic.

Call graph (cloud-mode init):

```
controlkeel init --org <slug> --workspace <slug> [--new-workspace <n>] [--user-id <id>]
  -> Dispatch.Core.run_command(:init)
       +- Mode.current() == :local -> warn if --org/--workspace present -> Local.init (default route)
       +- Mode.current() == :cloud -> Project.Cloud.init/2
            +- Accounts.get_org_by_slug/1
            +- Accounts.get_active_membership(user_id, org_id)   <- reject if nil
            +- Mission.get_workspace_by_slug/1 | Mission.create_workspace/1 (--new-workspace)
            +- error if workspace.org_id != selected org
            +- Mission.create_launch(%{workspace_id, org_id, ...}) -> binding writes org_id
```

Web onboarding (`OnboardingLive`) cloud picker:

```
mount: Mode.current(), @current_user / @current_membership (from :cloud_auth on_mount)
  local -> no UI change; create_launch falls back to default workspace
  cloud -> org select (Accounts.orgs_for_user) -> workspace select (Mission.list_workspaces_for_org)
  accept -> Mission.create_launch_from_brief(%{workspace_id: ...}, brief)
```

## 3. Concrete changes

### 3.1 CLI switches — `lib/controlkeel/cli/parser.ex`
Add to `@init_switches`:
```
org: :string, workspace: :string, new_workspace: :string, user_id: :integer
```
(Reuse the `--user-id` precedent already used by `run_cloud_agent`.)

### 3.2 Cloud init + local warning — `lib/controlkeel/cli/dispatch/core.ex`
Branch `run_command(:init)` on `Mode.current()`:
- **local:** if any of `options[:org] | options[:workspace] | options[:new_workspace]`
  is set, prepend a warning line (options are ignored; the default org/workspace
  is always used), then continue through the existing `Local.init` path.
- **cloud:** delegate to the new `ControlKeel.Project.Cloud.init/2` (3.3) when an
  org is selected. When org/workspace flags are absent, list the operator's orgs
  (`Accounts.org_ids_for_user`) and each org's workspaces, and return a clear
  error listing available orgs/workspaces with a pointer to pass `--org` /
  `--workspace` (non-interactive CLI; explicit selection is the safe default over
  a blocking TTY prompt).

### 3.3 Cloud init resolver — `lib/controlkeel/project/cloud.ex` (new)
`init(attrs, project_root)` that:
1. Resolves `user_id` from `--user-id`; error if the cloud operator is not
   identified.
2. Resolves the org by slug; if missing, or the user has no
   `Accounts.get_active_membership(user_id, org_id)`, error listing available
   orgs and stating membership is required.
3. Resolves the workspace by slug under that org; error if `workspace.org_id !=
   org.id`; if `--new-workspace <name>` given, `Mission.create_workspace/1`
   under the org and use it.
4. Calls `Mission.create_launch(%{workspace_id: ws_id, org_id: org_id, ...})`,
   then writes a binding with `org_id` reusing `Project.Local`'s binding helpers
   so the on-disk format stays consistent.

### 3.4 Web onboarding cloud picker — `lib/controlkeel_web/live/onboarding_live.ex`
- `mount`: assign `:mode`; in cloud and signed-in, load the operator's orgs
  (`Accounts.org_ids_for_user`) and the selected org's workspaces
  (`Mission.list_workspaces_for_org/1`). Default selection = `@current_membership`.
- Add an org + workspace `<.select>` step (rendered only when
  `@cloud_mode`), with a `phx-change` handler that repopulates workspaces when
  the org changes.
- On `accept`, pass the chosen `workspace_id` into
  `Mission.create_launch_from_brief/2` so the mission lands in that workspace.
  Local mode is unchanged (falls back to the default workspace).

### 3.5 Tests — new/updated
- `test/controlkeel/cli/` — cloud init success (org+workspace), membership
  rejection, wrong-org-workspace rejection, missing `--user-id`, and local-mode
  `--org` warning (assert the default org/workspace is used).
- `test/controlkeel/project/cloud_test.exs` (new) — `Project.Cloud.init/2`
  unit tests (membership gate, org/workspace resolution, `--new-workspace`).
- `test/controlkeel_web/live/onboarding_live_test.exs` — cloud-mode picker render
  + accept routing; keep existing local-mode tests green.

## 4. Acceptance-criteria mapping

| Issue AC | Where | Status |
| --- | --- | --- |
| Fresh project → one default org + workspace | `local_defaults.ex` / `mission.ex` | already on branch |
| Second project reuses same org/workspace | idem `LocalDefaults.ensure` | already on branch |
| Binding contains `org_id`; old bindings load | `binding.ex` | already on branch |
| Single orphan workspace auto-linked | `local_migration.ex` | already on branch |
| Multiple orphan workspaces warned, untouched | `local_migration.ex` | already on branch |
| `init --org acme --workspace backend` targets | §3.2/3.3 | **this PR** |
| `init` without flags prompts/picks | §3.2 | **this PR** |
| `--org` in local mode warns + uses default | §3.2 | **this PR** |
| Reject no-membership cloud init | §3.3 | **this PR** |
| Web onboarding org/workspace picker (cloud) | §3.4 | **this PR** |
| `mix precommit` passes | CI (Elixir 1.15) | verify in CI, §5 |

## 5. Risks / open decisions
- **Local `mix precommit` cannot run here** (Elixir 1.20 vs `~> 1.15`; `websockex`
  does not compile). Plan must run precommit in the CI image. Flag for the PR body.
- **Local budget default** — the issue audit recommends `nil` (no budget) for the
  local default workspace; the branch currently uses `budget_cents: 0`. Confirm
  `0` is interpreted as uncapped/neutral (not "block all sessions") before merge;
  if not, this PR should align the default to `nil` (small `local_defaults.ex` /
  `local_migration.ex` change). Keep this in scope of the new PR unless the team
  prefers to leave existing behavior.
- **Cloud CLI "operator" identity** — cloud `init` must know which user to check
  membership for. `--user-id` (already precedented by `run_cloud_agent`) is the
  minimal, non-interactive approach; keep it.
- **Interactive prompt vs. explicit flag** — this plan chooses explicit flags +
  a clear listing error over a blocking TTY prompt, because the CLI is
  automation-facing (`cli-for-agents`). If human-first prompting is desired,
  add an interactive branch gated behind a `--interactive` flag.

## 6. Out of scope (already handled or intentionally deferred)
- Schema/DDL changes (none needed).
- Local-mode hierarchy, default provisioning, migration, and workspace-visibility
  UI (done on the branch).