---
name: align
description: "Interview the user about their goal before any plan or code. Reach shared understanding of what, why, which layers, success criteria, and unknowns. Feed the result into plan-slice or ck_review_submit."
when_to_use: "Activate at the very start of any new feature, fix, or project — before writing a PRD, submitting a plan, or touching any code. Also activate when a brief or Slack message arrives and the intent is not yet fully clear."
argument-hint: "[goal description or raw brief]"
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
metadata:
  author: controlkeel
  version: "1.0"
  category: planning
  ck_mcp_tools:
    - ck_context
    - ck_goal
    - ck_memory_record
    - ck_memory_search
---

# Align Skill

Reach a **shared design concept** with the user before any plan or code is written. The most expensive misalignment is the one caught after implementation — catch it here instead.

## Protocol

1. Call `ck_context` to load current session state, domain pack, and any prior goals or decisions already recorded.
2. Call `ck_memory_search` with the user's stated goal to surface prior aligned work on the same area before asking redundant questions.
3. Ask the user **one question at a time**. For each question, provide your recommended answer so the user can confirm, adjust, or replace it — never leave them staring at a blank.
4. Work through the alignment tree in this order:

   **What** — What is the exact outcome? What is explicitly out of scope?
   **Why** — What problem does this solve? What is the success signal?
   **Who** — Who uses the result? Which roles, systems, or integrations are affected?
   **Layers** — Which system layers does this touch? (schema, services, APIs, UI, infra, third-party) Record each touched layer explicitly — this drives vertical slice decomposition later.
   **Acceptance criteria** — What does "done" look like? What would a failing test catch?
   **Edge cases** — What breaks if inputs are invalid, empty, or unexpected?
   **Constraints** — Budget, timeline, tech stack limits, compliance requirements, or must-not-change areas.
   **Unknowns** — What do you not know yet? What needs a spike or research before implementation starts?

5. After each resolved decision, call `ck_memory_record` with type `decision` to persist it. Future agents resuming this work will recover these without asking again.
6. When alignment is complete, call `ck_goal` (mode: `record`, horizon: `session`) to record the aligned goal with its acceptance criteria and touched layers.
7. Tell the user the alignment is complete and recommend the next step:
   - If the work is multi-layer and will need decomposition → activate `plan-slice`.
   - If the work is a single small change that fits in one task → proceed to `ck_review_submit` (plan_phase: `narrowed_decision`).

## Non-negotiable rules

- Never skip alignment and go straight to planning or code, even for "small" tasks. A missed constraint at this stage compounds into blocked findings or rework later.
- Do not produce a plan, PRD, or code during this skill. The output is a recorded goal and a set of decisions — nothing else.
- If the user says "just do it," record what you know so far, note the unknowns explicitly, and move forward — but surface the open questions as warnings so they can surface as findings if they bite later.
- Planning is always human-in-the-loop. The agent asks; the human decides. Never answer your own alignment questions and continue as if the human agreed.

## What you produce

At the end of this skill:
- A `ck_goal` record with: objective, acceptance criteria, touched layers, known constraints, open unknowns.
- One or more `ck_memory_record` entries (type: `decision`) for each resolved design choice.
- A clear recommendation on whether to proceed to `plan-slice` or directly to `ck_review_submit`.

## Additional resources

- For the full governed workflow, see [references/workflow.md](references/workflow.md)
