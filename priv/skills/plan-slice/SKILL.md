---
name: plan-slice
description: "Decompose an aligned goal into independently executable vertical slices with explicit blocking relationships. Each slice must cross all touched system layers — not a single layer. Submit for human approval before any implementation begins."
when_to_use: "Activate after the align skill has produced a recorded goal, and before any code or delegation begins. Also activate when a goal has more than one system layer or more than two sequential tasks."
argument-hint: "[aligned goal or ck_goal record ID]"
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
  - cline-native
  - cursor-native
  - windsurf-native
  - continue-native
  - letta-code-native
  - pi-native
  - roo-native
  - goose-native
  - opencode-native
  - antigravity-cli-native
  - kiro-native
  - kilo-native
  - amp-native
  - augment-native
  - devin-terminal-native
  - warp-native
  - droid-bundle
metadata:
  author: controlkeel
  version: "1.0"
  category: planning
  ck_mcp_tools:
    - ck_context
    - ck_goal
    - ck_memory_record
    - ck_memory_search
    - ck_review_submit
    - ck_review_status
    - ck_route
---

# Plan Slice Skill

Turn an aligned goal into a **directed acyclic graph of vertical slices** that agents can execute independently. Vertical slices give you working software at the end of each slice and feedback across all layers immediately — not at the end of phase 3 when three layers have already diverged.

## Why vertical slices matter

Agents default to horizontal work: all schema changes in phase 1, all API changes in phase 2, all UI in phase 3. This delays feedback on whether layers actually fit together until late in the work. A vertical slice crosses schema + service + UI (or whichever layers are touched) in one shot, so each slice is demonstrably working software — not a half-built layer.

## Protocol

### 1. Load context
Call `ck_context` and `ck_memory_search` to retrieve the aligned goal, recorded decisions, and touched layers from the `align` step.

### 2. Map system layers
List every layer the goal touches. Common layers in order (innermost first):
- **schema** — database tables, migrations, indexes
- **service** — business logic, background jobs, domain rules
- **api** — HTTP handlers, resolvers, RPC endpoints
- **ui** — components, pages, forms, interactions
- **infra** — CI/CD, environment config, feature flags, third-party credentials

Not every goal touches all layers. Record which ones are in scope.

### 3. Draft vertical slices

Each slice must:
- Touch **at least two adjacent layers** from the list above (one-layer slices are horizontal — flag them and expand or merge).
- Deliver something observable or testable at its boundary (a working endpoint, a rendered component, a passing integration test).
- Be **independently grabbable**: another agent or developer can pick it up given only the slice description and the outputs of its blocking slices.

Start with the **thinnest possible vertical slice first** — often called the tracer bullet. This is the minimal path through all touched layers: one user story, one schema column, one endpoint, one UI element. It proves the layers fit together before you build breadth.

Structure:
```
Slice 1 (tracer): <minimal cross-layer path> — AFK
Slice 2: <next user story, depends on slice 1> — AFK
Slice 3: <requires a design decision> — HiTL
Slice 4: <final integration / edge cases, depends on 2 and 3> — AFK
```

### 4. Validate each slice

For every proposed slice, check:
- Does it touch only one layer? → **Horizontal slice — expand or merge.**
- Does it produce something testable by the end? → If not, split differently.
- Could another agent start it in isolation given its inputs? → If not, clarify the interface contract.
- Does it contain unresolved design decisions? → Label it **HiTL** (supervised_execute or human_gate); clear decisions → label **AFK** (guarded_autonomy).

### 5. Define blocking relationships

Produce an explicit dependency list:
```
Slice 2 blocked by: Slice 1
Slice 3 blocked by: Slice 1
Slice 4 blocked by: Slice 2, Slice 3
```

Slices with no dependencies can run in parallel via `ck_route` + `ck_delegate`. Document which slices are parallelizable.

### 6. Label autonomy mode per slice

Map each slice to a CK autonomy profile:
- **AFK** → `guarded_autonomy`: well-defined inputs/outputs, no open design questions, validation loop is deterministic.
- **HiTL** → `supervised_execute`: contains a design decision, requires human judgment, or touches a critical path (auth, payments, schema migration, compliance-sensitive data).

Never label a slice AFK if it contains an unresolved unknown from the `align` step.

### 7. Define success criteria for each slice

For every slice, convert vague requirements into concrete, testable conditions:

**Example:**
```
VAGUE: "Make the dashboard faster"
REFRAMED SUCCESS CRITERIA:
- Dashboard LCP < 2.5s on 4G connection
- Initial data load completes in < 500ms
- No layout shift during load (CLS < 0.1)
```

Each slice must have:
- Observable success condition (what you can measure or verify)
- Failure condition (what would indicate the slice is not done)
- Edge case coverage (what breaks if inputs are invalid)

### 8. Record the plan
Call `ck_memory_record` (type: `decision`) with the full slice plan: slice titles, layer coverage, blocking relationships, autonomy labels, and success criteria.

Update the `ck_goal` record (mode: `update_status`) with `active` and a progress note pointing to the slice plan.

### 9. Submit for human approval

Call `ck_review_submit` with:
- `review_type`: `plan`
- `plan_phase`: `implementation_plan`
- `implementation_steps`: the slice list with blocking relationships, autonomy labels, and success criteria
- `validation_plan`: which tests or observables prove each slice is done
- `alignment_context`: the accepted goal from the `align` step
- `scope_estimate`: number of slices, estimated touch points per layer

Then call `ck_review_status` to check for `grill_questions`. Surface every grill question back to the user and resolve them before implementation begins. This is still human-in-the-loop — do not start coding until the review is approved.

## Non-negotiable rules

- Never begin implementation before the review is approved.
- A slice that touches only one layer is not a vertical slice — it is a horizontal slice. Reject it.
- AFK slices must have zero open design questions. If you find one, promote the slice to HiTL.
- Parallelism is only valid between slices with no blocking relationship. Never run blocking slices in parallel.
- The first slice must always be the thinnest viable cross-layer path. Do not start with setup or scaffolding that produces no observable output.

## What you produce

At the end of this skill:
- A reviewed and approved slice plan (via `ck_review_submit`).
- A `ck_memory_record` containing the DAG: slice titles, layers, dependencies, autonomy labels, and success criteria.
- A `ck_goal` update marking the plan as active.
- A clear first slice ready for handoff to implementation (via `ck_delegate` or direct agent work under the governance skill).

## Additional resources

- For the full governed workflow, see [references/workflow.md](references/workflow.md)
