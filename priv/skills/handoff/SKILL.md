---
name: handoff
description: "Persist session state and hand off in-progress work to a background agent — the *delegation step* of `end-of-shift`. Use when work outgrows the current session or must continue unattended; for a full session close (validation + proof + findings + budget + digest + learning before handoff) prefer `end-of-shift`."
when_to_use: "Activate ONLY for mid-session delegation (context near limit, `ck_route` recommends a different agent/runtime, user says hand off/delegate/pass off). For an end-of-shift wrap-up (validate remaining work, finalize proofs, synthesize learnings), use `end-of-shift` instead — `handoff` is that skill's final step."
argument-hint: "[optional: specific task or remaining work to hand off]"
disable-model-invocation: true
license: Apache-2.0
redirect_to: end-of-shift
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
  version: "1.1"
  category: execution
  superseded_by: end-of-shift
  ck_mcp_tools:
    - ck_context
    - ck_memory_record
    - ck_memory_search
    - ck_route
    - ck_delegate
    - ck_goal
---

# Handoff Skill — delegation step

> This skill is the **delegation sub-step** of `end-of-shift`. A full end-of-shift
> run validates remaining work, finalizes proofs, records digests/learnings, and THEN
> hands off. Use this skill alone only for mid-session delegation; otherwise prefer
> `end-of-shift`.

Transfer in-progress work to another agent or execution context with full state preservation, so work continues seamlessly after the current session ends or context runs out.

## When to use this skill

- Context window is approaching its limit and substantial work remains
- The user wants work to continue unattended (background execution)
- `ck_route` recommends a different agent or runtime for the remaining task
- The user explicitly asks to delegate, hand off, or pass work to a background agent

## Protocol

1. Call `ck_context` to load current session state, open findings, active goal, and proof summary.

2. Call `ck_memory_search` with the current task description to surface any prior decisions, constraints, or context that the receiving agent will need.

3. Build the **handoff packet** — record it with `ck_memory_record` (type: `decision`, scope: `session`) containing:
   - **What was accomplished** this session (bullet list of completed work with file paths)
   - **What remains** (ordered list of next steps, from most to least critical)
   - **Open findings** — any blocked or warning-level issues the receiving agent must address first
   - **Constraints** — must-not-change areas, budget limits, compliance requirements discovered this session
   - **Assumptions** — decisions made without explicit human confirmation that the receiving agent should be aware of
   - **Resume hint** — the single most important thing the next agent should do first

4. Call `ck_goal` (mode: `read`) to confirm the goal record is current. If it has drifted from what was actually worked on, update it with `ck_goal` (mode: `record`) before handing off.

5. Call `ck_route` to determine the best agent or execution mode for the remaining work. Provide the remaining task list and any constraints.

6. Call `ck_delegate` with the handoff packet as context and the routing recommendation from step 5. Use mode `handoff` for human-mediated transfer or mode `runtime` for automated background execution.

7. Confirm to the user:
   - What was preserved (memory record ID)
   - Where the work is going (agent / mode)
   - The single next action for the receiving agent
   - How to resume: what to tell the next agent to pick up seamlessly

## Non-negotiable rules

- Never hand off with open **blocked** findings. Resolve or escalate them first — a blocked finding handed off unresolved will stall the receiving agent immediately.
- The handoff packet must be complete enough that the receiving agent can continue **without** reading this session's conversation history.
- If `ck_route` returns no suitable agent, tell the user explicitly rather than handing off to a mismatched executor.

## What you produce

At the end of this skill:
- A `ck_memory_record` entry (type: `decision`) containing the full handoff packet
- A `ck_delegate` call that initiates the transfer
- A clear user-facing summary: what was saved, where work is going, and what the next agent will do first

## Additional resources

- For proof preservation before handoff, run the `proof-memory` skill first
- For routing decisions, see `ck_route` tool documentation
