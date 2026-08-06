# PR: Cloud-mode org/workspace targeting → `refactor/org-workspace-relation`

## Metadata

|             |                                                                       |
| ----------- | --------------------------------------------------------------------- |
| **Head**    | `refactor/cloud-org-workspace-relation`                               |
| **Base**    | `refactor/org-workspace-relation` (clean ancestor — fast-forwardable) |
| **Commits** | 6                                                                     |
| **Scope**   | 15 files, ~1507 insertions / ~97 deletions                            |
| **Spec**    | `docs/org-mission-relation-issue.md`                                  |
| **Review**  | `docs/org-mission-relation-review.md`                                 |
| **Tests**   | 2145 passed, 0 failed, 1 excluded                                     |

---

## 1. What this PR does

The base branch (`refactor/org-workspace-relation`) enforces the Session → Workspace → Org hierarchy for **local** mode: a single default org + default workspace, every `init` adds a session to it, `org_id` recorded in the binding, in-app data migration, workspace detail UI.

This PR layers **cloud-mode** on top. It adds the org/workspace **selection** the issue's cloud acceptance criteria require, on two surfaces:

- **CLI:** `controlkeel init --org <slug> --workspace <slug>` targeting, interactive prompts when flags are omitted, and `workspace create` / `org create --default-workspace` commands. Local mode denies these org-admin commands.
- **Web onboarding (`/missions/start`):** the page is now **mode-aware** — local mode routes silently to the default workspace; cloud mode shows an org/workspace picker and gates onboarding on an owner/admin role.

---

## 2. Files changed

### Core init path

- **`cloud.ex`** — New `Project.Cloud` module: `init/2`, `create_and_bind/2`, `validate_targeting/1`, `resolve_org/1`, `resolve_workspace/2`, interactive prompts, slug-error helpers. Documents the deferred membership gap (§3.3).
- **`accounts.ex`** — `list_orgs_for_user/2` gains optional `min_role`; onboarding passes `"admin"` so the picker shows only owner/admin orgs. `/organizations` still calls arity-1 (all orgs).

### CLI

- **`cloud_selfhost.ex`** — `org create` (with `--default-workspace`), `workspace create`, cloud `init` dispatch. Documents the no-identity gap (CLI-created orgs get no owner membership).
- **`parser.ex`** — `:org`, `:workspace` switches on `init`; `@org_create_switches`, `@workspace_create_switches`; `workspace create` route.
- **`cli.ex`** — `@local_mode_denied_commands` denies `:org_create`/`:org_invite`/`:org_members`/`:workspace_create` in local mode, with actionable messages.
- **`core.ex`** — Wires the local-mode deny + the `--org`/`--workspace` warning when passed in local mode.
- **`catalog.ex`** — Registers the new command.

### Web

- **`onboarding_live.ex`** — Mode-aware mount, org/workspace discovery + selection, `:can_onboard`/`:cloud_mode` gates, `workspace_id` injection on accept, `{:error, :workspace_not_found}` clause, selector panel. Restored duplicate project-name pre-check (`Mission.project_name_taken?/1`).
- **`organizations_live.ex`** — Org index updates for the role surface.

### Tests & docs

- **`onboarding_live_test.exs`** — 12 onboarding tests: full local flow, dup-name block, cloud picker, no-org block, no-workspace block, member-exclusion, workspace repopulation on org select.
- **`docs/*`** — Issue, review, cloud-mode plan docs.

---

## 3. Acceptance criteria status

### Hierarchy + defaults (owned by base branch; carried forward)

- [x] `controlkeel init` in a fresh project creates one org + one workspace linked to it.
- [x] A second project reuses the same org/workspace; only a new session is added.
- [x] The binding file contains `org_id`.
- [x] Existing binding files without `org_id` still load.
- [ ] A local DB with a **single** orphan workspace gets it auto-linked **and renamed** to the default. _(3.2 — the migration consolidates + deletes instead of renaming in place.)_
- [ ] A local DB with **multiple** orphan workspaces gets a warning and is **left untouched**. _(3.2 — the migration consolidates + deletes them all.)_
- [x] `mix precommit` / full suite passes (2145 passed).

### Cloud mode (this PR)

- [x] `controlkeel init --org acme --workspace backend` targets the specified org/workspace.
- [x] `controlkeel init` without flags prompts the user to pick an org and workspace.
- [x] Passing `--org` in local mode prints a warning and uses the default anyway.
- [ ] Cloud-mode init **rejects users without membership** in the selected org. _(3.3 — the CLI has no user identity yet; see "Known gaps".)_
- [x] The web onboarding page shows an org/workspace picker in cloud mode.

---

## 4. Known gaps (deferred, documented in code)

These are intentional deferrals, each documented at the call site and in `docs/org-mission-relation-review.md`.

### 4.1 CLI membership authorization (review §3.3 — High)

`Project.Cloud.resolve_org/1` resolves an org by slug but does **not** validate that the caller has an active membership. Reason: the CLI has no notion of a "current user" — no login, stored token, or `whoami`. Until CLI identity exists, the membership check cannot be wired. Documented in `cloud.ex` at `resolve_org` and in `cloud_selfhost.ex` (`TODO(ck-cli-auth)`). **The web onboarding path does gate on `current_membership`** (owner/admin) because it has a signed-in user; the CLI cannot, yet.

### 4.2 `--new-workspace` flag (review §3.5 — Low)

The issue (§1.6) asked for `--new-workspace <name>` to create a workspace inline during `init`. Not implemented. Workaround: `controlkeel org create <slug> --default-workspace` or `controlkeel workspace create` first, then `init --workspace <slug>`.

### 4.3 Workspace-level budget gating (review §3.4 — Medium)

Workspace `budget_cents` displays but does not gate sessions. `Budget` reads session-level `budget_cents`/`daily_budget_cents` only. The default workspace uses `budget_cents: 0` (no gate), so there is no surprise trip — but per-workspace enforcement is not wired.

### 4.4 Migration policy (review §3.2 — Blocking, owned by base branch)

`Bootstrap.LocalMigration` consolidates all sessions into the default workspace and hard-deletes empty non-default workspaces/orgs, **regardless of orphan count**. This deviates from the issue's policy (single orphan → rename in place; multiple orphans → leave untouched + warn). The behavior is documented in the module as intentional. **Reconcile with the spec or obtain explicit sign-off before release.**

---

## 5. Verification

- Full suite: **2145 passed, 0 failed, 1 excluded** (performance).
- `onboarding_live_test.exs`: 12 tests covering local flow, duplicate-name block, cloud picker, no-org/no-workspace blocks, member exclusion, and workspace repopulation.
- The historical websockex/Elixir-1.20 compile blocker is resolved locally (patched `deps/websockex/mix.exs` charlist→string); upstream fix is `mix deps.update websockex`.

---

## 6. Reviewer notes

- The base branch is a **clean ancestor** — this PR fast-forwards cleanly; no merge conflicts expected.
- The web onboarding change is the largest surface (`onboarding_live.ex` +284). The cloud picker restricts orgs to owner/admin via `list_orgs_for_user(user.id, "admin")`; `/organizations` is unchanged and still lists all orgs.
- Two pre-existing `organizations_live_test` `>Role<` assertions fail on the base branch already (no "Role" column rendered); they are **not introduced by this PR**.
- Recommended review order: `project/cloud.ex` (the new init path) → `cloud_selfhost.ex` (CLI commands + the identity-gap TODO) → `onboarding_live.ex` (mode-aware web) → tests.
