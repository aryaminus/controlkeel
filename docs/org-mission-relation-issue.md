## Context

When you run `controlkeel init` inside a project folder, it creates a session. The session needs a workspace to live in, and the workspace needs to belong to an org. Today the CLI derives the workspace name from the project name — so "ticketing-app" and "controlkeel" each get their own workspace. No org is ever created or linked. Every workspace ends up orphaned with no org, and the number of workspaces grows with every new project.

The binding file on disk (`controlkeel/project.json`) records which workspace and session the project is bound to, but not the org.

## Problem

- `controlkeel init` creates a new workspace per project and never links an org — local users get workspace sprawl with zero orgs.
- Workspaces are invisible — no web page, no CLI command. Users don't know they exist.
- Org-level and workspace-level policies (budgets, compliance, tool policies) are silently bypassed because workspaces have no org.
- Cloud-mode users have no way to target a specific org or workspace during init — the CLI has no flags for selection, and the web onboarding page ignores the signed-in user's org.

## Goal

Establish the full Session → Workspace → Org hierarchy so that every session belongs to a workspace, and every workspace belongs to an org:

- Use a single **Default Organization** (slug: `default-organization`) for all local-mode sessions.
- Use a single **Default Workspace** (slug: `default-workspace`) under the default org.
- Every `controlkeel init` adds a new session to the default workspace — never creates a new workspace or org.
- Record `org_id` in the binding file so the project knows its org.
- Intentionally limit local users to one org and one workspace — needing more is the signal to move to cloud mode.
- Enable org-level and workspace-level policies to actually apply to sessions instead of being silently bypassed.
- In cloud mode, let the user choose an existing org and workspace via CLI flags or interactive prompts.
- Validate that the user has an active membership in the selected org (cloud mode only).

**Local mode shape:** 1 org → 1 workspace → N sessions (one per project).

## Proposed changes

### 1.1 Create default org if missing

When `controlkeel init` runs, check if an org named "Default Organization" (slug: `default-organization`) already exists. If not, create it. If yes, reuse it. This is idempotent — running init again never duplicates the org.

### 1.2 Create default workspace if missing

Same pattern for the workspace: check if "Default Workspace" (slug: `default-workspace`) exists under the default org. If not, create it with sensible defaults (industry: general, agent: claude, budget: $30). If yes, reuse it. If an older workspace row exists without an org, backfill the org link.

### 1.3 Route new sessions into the existing workspace

When creating a session, if a target workspace is already specified, place the session directly into it — skip the "create a new workspace" step entirely. This applies to both the CLI init path and the web onboarding path.

### 1.4 Wire defaults into the init and bootstrap flows

Both the explicit `controlkeel init` command and the automatic MCP bootstrap path should ensure the default org and workspace exist before creating a session, then route the session into the default workspace.

### 1.5 Record org in the binding file

Add `org_id` to the binding file so the on-disk project knows which org it belongs to. Old binding files without `org_id` continue to work — the field is optional.

### 1.6 CLI flags for org/workspace selection (cloud mode)

Add optional flags to `controlkeel init`:

- `--org <slug>` — target an existing org by slug. If omitted in cloud mode, prompt interactively or list available orgs.
- `--workspace <slug>` — target an existing workspace by slug. If omitted in cloud mode, prompt or create new.
- `--new-workspace <name>` — create a new workspace under the selected org.

In local mode, these flags are ignored (the default org/workspace is always used). A warning is printed if the user passes them in local mode.

### 1.7 Web onboarding page

Update the "Start a session" page to be mode-aware:

- **Local mode:** Auto-create the default org and workspace if they don't exist, then route the session into the default workspace silently — no user interaction needed.
- **Cloud mode:** Show an org/workspace selector so the user picks where the session goes.

## Migration policy for existing data

Local databases created before this change may contain orphan rows that need a defined policy:

- **Orphan workspaces (org_id is NULL):** On first run of the updated `controlkeel init`, scan for workspaces with no org. If exactly one workspace exists, link it to the default org and rename it to "Default Workspace" (slug: `default-workspace`). If multiple orphan workspaces exist, leave them untouched and create the default workspace alongside them — the user can migrate or clean up manually via the workspaces page. Log a warning so the user knows orphan workspaces exist.
- **Orphan orgs (exist with no workspaces):** Same policy as workspaces. In local mode, multiple orgs are not allowed — if exactly one orphan org exists, leave it as-is (it becomes the default). If multiple orphan orgs exist, warn the user; local mode should have only one. In cloud mode, migration is not a major concern — multiple orgs are expected and left untouched.
- **Existing binding files (no org_id):** Continue to load. The next `controlkeel init` in that project rewrites the binding with `org_id` populated. No forced migration.
- **Existing sessions bound to orphan workspaces:** Continue to work. Their workspace retains its old name and slug. Only the default workspace gets the fixed name/slug.

## Acceptance criteria

**Hierarchy + defaults:**

- [ ] `controlkeel init` in a fresh project creates exactly one org ("Default Organization") and one workspace ("Default Workspace") linked to that org.
- [ ] `controlkeel init` in a second project reuses the same org and workspace; only a new session is added.
- [ ] The binding file contains `org_id`.
- [ ] Existing binding files without `org_id` still load.
- [ ] A local DB with a single orphan workspace gets it auto-linked to the default org on next init.
- [ ] A local DB with multiple orphan workspaces gets a warning; those workspaces are left untouched.
- [ ] `mix precommit` passes.

**Cloud mode:**

- [ ] `controlkeel init --org acme --workspace backend` targets the specified org/workspace.
- [ ] `controlkeel init` without flags prompts the user to pick an org and workspace.
- [ ] Passing `--org` in local mode prints a warning and uses the default anyway.
- [ ] Cloud-mode init rejects users without membership in the selected org.
- [ ] The web onboarding page shows an org/workspace picker in cloud mode.

## Edge cases

- **Slug collisions:** The fixed slugs (`default-organization`, `default-workspace`) are reserved. If a row with that slug exists under a different name, creation fails loudly rather than silently overwriting.
- **Idempotency:** Re-running `init` in a project that already has a valid binding is a no-op — it does not rewrite the binding or create duplicate rows.
- **Database wiped between inits:** If the DB is cleared but the binding file still references old IDs, init detects the missing session and recreates everything from scratch (existing behavior, preserved).
- **Invalid org/workspace slug (cloud):** Fail with a clear error listing available orgs/workspaces.
- **User has no orgs in cloud mode:** Prompt to create one first, link to the org creation page.
- **Workspace belongs to a different org:** Reject with a clear error.

## Diagram
<img width="1536" height="1024" alt="Image" src="https://github.com/user-attachments/assets/a2e0e530-313f-4f1f-8bc6-3e3383fdc4d3" />


## Architecture + docs audit

Compared the proposal against the current codebase (`Workspace`, `Session`, `Org` schemas, `Project.Local` binding, `Mission.create_launch`, `config/runtime.exs`) and the relevant docs (`getting-started.md`, `control-plane-architecture.md`, `self-hosting.md`, `api-reference.md`, `cli-reference.md`, `support-matrix.md`). Short version: **the proposal is well-aligned with the existing schema; the hierarchy already exists in code — it just isnt enforced in the init path.**

### 1. The hierarchy already exists (this is good)

The schemas are correct:

- `Workspace` has `belongs_to :org, Org` — `org_id` is cast but **not required** in the changeset. Today, `Mission.create_launch/1` creates a workspace with `org_id: nil` — the orphaned state the proposal aims to fix.
- `Session` has `belongs_to :workspace, Workspace` — no `belongs_to :org`. Correct: Session → Workspace → Org is the proper traversal, and the introduction to the question states it.
- `Binding.write/2` currently writes `workspace_id` and `session_id` but **no `org_id`**.

So the proposal is not introducing a new schema; it is **enforcing a hierarchy that the schema already expresses but the init path bypasses**. That is the right kind of change.

### 2. What the docs say (and what they do not)

- `getting-started.md` says `controlkeel setup` — it never mentions orgs, workspaces, or the init flow. The proposal says `controlkeel init`. These need to be reconciled — either the doc must update, or the command names must match. `controlkeel init` is already listed in `cli-reference.md` (line 37: `controlkeel init # bootstrap a project`), so both commands exist; `setup` is the first-run path, `init` is per-project.
- `control-plane-architecture.md` says “workspace-scoped” and mentions “org data” — the proposals org/workspace scoping is consistent with the architecture document.
- `self-hosting.md` mentions org membership and workspace registration — consistent.
- There is **no document** explaining the Org → Workspace → Session model to users. The proposal would benefit from a short doc page added alongside the implementation, otherwise the “why do I see everything in one workspace” question will recur.

### 3. Three engineering realities the implementation must handle

#### 3a. Local mode has no persisted “user” for `create_org_with_owner/2`

`Accounts.create_org_with_owner/2` takes a `user_id` and inserts an owner membership. Local mode runs without authentication — the “current_user” is a struct but may not correspond to a persisted `users` row. The org-creation path must either seed a local user first, or use a `create_org/1` (no owner) and separately handle the owner. The proposal does not address this, and it is the most likely impl crash on first local `init`.

#### 3b. `Mission.create_launch/1` creates a new workspace per call

The current init flow calls `Mission.create_launch(launch_attrs)` which internally calls `Mission.create_workspace/1` to get a fresh workspace. The proposals goal (every session under the same workspace) requires the init path to **pass an existing `workspace_id`** into the launch, bypassing workspace creation entirely. The API for this exists (`create_launch` can accept a workspace) but the init path has never used it. This is a small but specific refactor — the “ensure default workspace exists” check must happen BEFORE `create_launch`, not inside it.

#### 3c. Workspace schema already allows `org_id: nil` — migration is data, not DDL

The “orphan workspace” migration described in the proposal is a **data migration** (UPDATE workspaces SET org_id = …), not a DDL migration (ALTER TABLE ADD). The schema is already ready. The migration should run on first init, not as an Ecto migration, because (a) it touches user data with heuristics and (b) it may log warnings. An Ecto migration is the wrong vehicle for conditional, heuristic-backed data migration with user-facing warnings.

### 4. One design concern: cross-project sessions in one workspace

The current model has workspace-per-project isolation. The proposal deliberately collapses that into one workspace. The trade-off:

- **Pro**: Policies (budgets, compliance, tool rules) that were bypassed before now actually apply. The dashboard shows a unified view.
- **Con**: Session-level data from unrelated projects (findings, tasks, proofs, budget spend) now co-mingle. A $30 budget on the workspace gates ALL projects — one expensive session can exhaust the budget for others. The observability dashboard blends project data unless filtered by session.

The proposals response (“needing more is the signal to move to cloud”) is valid but should be documented explicitly. The getting-started guide should call this out: “All local projects share one workspace. If you need per-project budgets or isolation, use cloud mode.”

The budget concern is the sharpest edge. A hardcoded $30 default (section 1.2) will surprise a user whose first agent session instantly trips it. I would default to `nil` (no budget) for local mode and leave the gate open until the user explicitly sets a budget.

### 5. Things that are solid and well-designed

- **Slug-collision safety**: fail loud, do not silently overwrite. Correct.
- **Idempotency**: re-running init in a bound project is a no-op. Correct.
- **Backward compatibility**: old binding files load, old orphan workspaces still work. Correct.
- **Cloud-mode membership check**: the proposal explicitly calls for validating `get_active_membership`. Critical path — must integrate with the membership model from PR #45.
- **Edge-case coverage**: deleted-session recovery, wiped DB, invalid org/workspace slugs, wrong-org workspace — all listed and thought through.

### 6. Missing: workspace visibility

PR #45 added organization detail and membership management, but there is no workspace list page or workspace detail. If the proposal creates a default workspace, users need to see it somewhere. The web onboarding page (section 1.7) is the right place, but consider adding a workspace selector to the org detail page (or a dedicated `/workspaces` page) so users can see what workspace their sessions are under.

---

## Judgment

The proposal is **architecturally sound and ready for implementation**, with the caveats above. The hierarchy exists in the schema; the proposal is the enforcement layer. The most important implementation details to get right:

1. Local-mode org owner (the user-seed problem).
2. Budget default should be `nil`, not `$30`, for local mode.
3. The data migration should be in-app (init-time), not an Ecto migration.
4. Cross-project budget sharing must be documented.
5. Workspace visibility needs a UI surface (even minimal — a label on the org detail page).

None of these are design-level blockers. They are implementation details to watch for in the PR that implements this.