execute as a senior Elixir/Phoenix engineer

# Session-Scoped Navigation Plan
based on issue: https://github.com/aryaminus/controlkeel/issues/130

## Decision Summary

ControlKeel currently presents session-specific work through a mixture of the large Mission Control page, workspace-scoped pages, and globally named `/findings`, `/proofs`, and observability pages. That makes the operator leave the session context to answer questions that belong to one governed run.

The first implementation slice will add a session dashboard surface while preserving the existing org/workspace-prefixed URL shape and the current dashboard layout. It will be implemented from the session-onboarding feature branch created for this work. Removing `/dashboard`, replacing the dashboard layout, and changing existing observability URLs are later migrations, not prerequisites for this slice.

## Current State

The relevant ownership boundaries are:

- `lib/controlkeel_web/router.ex`: cloud-auth LiveView sessions, organization-scoped session routes, and existing observability routes.
- `lib/controlkeel_web/components/organization_layouts.ex`: organization/workspace/session sidebar selection, breadcrumbs, and sibling session switching.
- `lib/controlkeel_web/components/layouts.ex`: global dashboard sidebar and observability navigation.
- `lib/controlkeel_web/live/mission_control_live.ex`: session authorization, two-second refresh, session assigns, task mutations, finding decisions, proof generation, release readiness, observability summary, memory, transcript, proxy endpoints, and the large overview template.
- `test/controlkeel_web/live/mission_control_live_test.exs`: current behavioral coverage for task graphs, findings, observability, reviews, launch state, refresh, fixes, and task controls.

The organization layout already detects `nav_session` and supplies a session navigation list. Today that list contains only Overview, Reviews, and Deploy review. This is the nearest existing seam for a session dashboard and should be extended before introducing a second chrome system.

## Target Information Architecture

The entity hierarchy should be explicit:

```text
Organization -> Workspace -> Session -> Task
```

The session sidebar should contain only views whose primary data is constrained to the current session:

| Navigation item | Initial route shape                                    | First implementation boundary                                                                              |
| --------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| Overview        | `/:org_slug/workspaces/:ws_slug/sessions/:id`          | Keep Mission Control as the session summary and reduce it as sections move out.                            |
| Tasks           | `/:org_slug/workspaces/:ws_slug/sessions/:id/tasks`    | New session task index; expose task status, dependencies, proof state, and controls.                       |
| Findings        | `/:org_slug/workspaces/:ws_slug/sessions/:id/findings` | New session finding index; preserve finding decisions and guided fixes.                                    |
| Proofs          | `/:org_slug/workspaces/:ws_slug/sessions/:id/proofs`   | New session proof index; link task evidence and verification state.                                        |
| Reviews         | Existing session reviews route                         | Retain the existing page and make it part of the session navigation contract.                              |
| Deploy review   | Existing session deploy-review route                   | Retain the existing page and make its session scope explicit.                                              |
| Observability   | Additive session-scoped route family                   | Start with links/pages for timeline, memory, and the existing run summary; defer removal of legacy routes. |

Task detail routes may follow the initial index route once the task ownership boundary is confirmed. A likely follow-up is `.../sessions/:id/tasks/:task_id`, but it should not be added until task authorization and proof ownership are tested.

Global `/findings`, `/proofs`, `/benchmarks`, `/policies`, and `/skills` remain available during this work. They should continue to serve cross-session or workspace-level workflows until a separate scope review changes their contracts.

## Implementation Slices

### Slice 1: Lock the session chrome and route contract

1. Extend `session_nav_items/3` in `OrganizationLayouts` with the agreed session destinations and stable active-state rules.
2. Add route declarations under the existing organization `live_session`, keeping the parameterized organization block last in the router.
3. Centralize or reuse the session access and slug agreement check. Every new LiveView must reject an inaccessible session and a mismatched organization/workspace slug with the same generic not-found behavior as Mission Control.
4. Define the session layout contract: `nav_org`, `nav_workspace`, `nav_session`, breadcrumbs, sibling sessions, current path, and page title must be assigned consistently for every session page.
5. Add route and sidebar tests before extracting large templates.

**Exit criteria:** every proposed session route has an active sidebar item, direct navigation enforces access and scope, sibling-session switching preserves the current subpage where valid, and mismatched slugs do not disclose session existence.

### Slice 2: Extract the Overview into a deliberate session dashboard

1. Keep `MissionControlLive` as the Overview owner initially.
2. Group the existing template into explicit sections: session health/metrics, current task, task graph/checklist, release readiness, execution brief/boundary, and recent activity.
3. Replace cross-surface links that lose session context with the new session routes.
4. Keep the refresh loop and mutation handlers in the owner of the data they refresh. Do not duplicate `safe_assign_session/2`, release readiness refresh, or authorization logic in child pages.
5. Move purely presentational sections into function components only when the component has a clear input contract and focused tests.

**Exit criteria:** Overview remains behaviorally equivalent for existing controls, has no dead links, and makes the session scope visible in headings, breadcrumbs, and navigation.

### Slice 3: Add the session Tasks page

1. Derive the page from `Mission.session_task_graph/1`, the session task collection, proof summaries, and existing task mutation APIs.
2. Keep task actions server-authorized by session/task ownership; do not trust a session id supplied only by the browser event.
3. Display dependencies, readiness, status, validation gate, rollback boundary, verification evidence, and links to proof/task detail where supported.
4. Reuse the existing completion, pause, resume, and proof-generation behavior through a narrow shared component or context API rather than copying event handlers.

**Exit criteria:** task status changes refresh the session page, unresolved findings and proof gates retain their current blocking behavior, and task actions cannot cross session boundaries.

### Slice 4: Add session Findings and Proofs pages

1. Add session-filtered queries in the owning context, not by loading global collections and filtering in the template.
2. Preserve the current finding decision flow: approve, reject with an optional reason, view guided fix, and copy the fix prompt.
3. Preserve proof-to-task and proof-to-session relationships and show verification strength, deploy readiness, and latest proof state.
4. Keep global browser routes intact and add explicit links back to the current session when an operator enters a global page.

**Exit criteria:** session pages cannot display another session's records, existing finding/proof actions retain telemetry and audit behavior, and empty/error states are covered.

### Slice 5: Make session Observability navigable

1. Add session navigation links for the existing session observability summary, timeline, and memory surfaces.
2. Prefer the existing session observability layout and components where possible; do not create a parallel sidebar.
3. Keep legacy `/observability/sessions/:id/*` routes working during the additive phase.
4. Plan redirects and canonical URL changes separately after all links, exports, tests, and documentation have been inventoried.

**Exit criteria:** an operator can reach health, events, memory, findings, gates, proofs, and cost from the session chrome without using a global sidebar, while legacy links remain functional.

## Authorization and Data Invariants

- Every session page must run the authenticated session-access check before using org/workspace slug agreement as a routing check.
- Session id, task id, finding id, and proof id must be validated against the authorized session in the context/query boundary.
- A generic not-found response should be used for missing, inaccessible, or scope-mismatched records to avoid existence disclosure.
- Session-filtered queries must be enforced in the context layer. Template-level filtering is not an authorization boundary.
- Mutations must retain the current actor attribution, telemetry, audit-log behavior, and proof/readiness gates.
- Shared session assigns and navigation must have one owner. New pages should not independently reconstruct the session, workspace, or organization from untrusted params.

## Testing Strategy

Add focused tests alongside each slice:

- Router tests for every new route and route precedence around the parameterized organization scope.
- Layout tests for session nav labels, active states, breadcrumbs, and sibling-session switching.
- Authorization tests for unauthenticated users, inaccessible sessions, mismatched org/workspace slugs, and cross-session record ids.
- LiveView tests for empty, populated, and refreshed states on Tasks, Findings, Proofs, and Observability.
- Mutation tests proving finding decisions, proof generation, task pause/resume/complete, and release-readiness behavior remain unchanged.
- Regression tests that global Findings and Proofs pages remain available during the migration.
- Link assertions from Overview to each session-scoped destination, avoiding raw HTML snapshots where a selector or visible outcome is sufficient.

Run the narrow LiveView test file after each slice, then run `mix precommit` before the migration is considered ready for review.

## Deferred Migration Work

These are intentionally outside the first slice:

1. Remove or repurpose `/dashboard` after session and organization navigation have adoption and coverage.
2. Remove the dashboard layout only after all consumers have moved to organization or session layouts.
3. Canonicalize session observability URLs and add redirects from the legacy route family.
4. Decide whether global Findings and Proofs become workspace browsers, remain global, or redirect into a selected session.
5. Reduce Mission Control further once the extracted pages have stable contracts and usage evidence.
6. Add task detail routes and task-specific navigation after task access rules are explicit.

## Review Checklist

- [ ] Branch is based on the existing session-onboarding work.
- [ ] Route map and session sidebar are approved before page extraction.
- [ ] No new global navigation item is used for a session-only workflow.
- [ ] All session pages use the same access and scope semantics.
- [ ] Tasks are included as a first-class session surface.
- [ ] Existing Reviews and Deploy review routes remain compatible.
- [ ] Legacy global and observability routes remain functional in the additive phase.
- [ ] Focused LiveView and authorization tests pass.
- [ ] `mix precommit` passes.
- [ ] Dashboard removal and layout replacement remain deferred until a separate migration review.
