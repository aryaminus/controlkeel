# Autonomy and Findings

Agents are often eager to execute arbitrary shell commands and file writes. ControlKeel introduces "Bounded Autonomy" through findings, gates, typed memory, and hook enforcement.

## Findings
When an agent attempts an action that violates a rule, exceeds budget, or fails a test, ControlKeel records a Finding.
- **Blocked:** The agent is halted and cannot proceed until a human intervenes or the issue is algorithmically resolved.
- **Escalated:** Human attention is requested but execution may continue in parallel.
- **Approved/Denied:** The final state of a human-gated finding.

Findings are recorded automatically on lifecycle events (session, task, review, proof, budget, regression) and can be created explicitly through `ck_finding`. Each finding writes a typed memory record so future agents recover the context without re-deriving it.

### Decision-time snapshots
When a finding or review is created, ControlKeel stamps decision-time metadata that survives later state changes:
- **Policy snapshot** — domain pack, policy packs, and a packs hash identifying the exact ruleset that governed the decision.
- **Artifact snapshot** — content SHA256, byte count, path, and kind of the reviewed artifact.
- **Model provenance** — provider, model, agent ID, and invocation reference, sourced from explicit metadata or the latest invocation.

These snapshots mean a historical decision can be replayed against the ruleset and content that governed it at decision time, not current mutable state.

### Finding disposition audit events
Every finding disposition (resolve, dismiss, escalate) writes an append-only `FindingAuditEvent` row recording:
- event type (approved, rejected, escalated)
- previous status and new status
- reason (for dismissals)
- actor source and actor identifier
- timestamp

These are immutable audit rows, separate from the mutable finding record, so disposition history cannot be retroactively rewritten.

### Precedent at decision time
When `ck_validate` or `ck_finding` handles a rule, ControlKeel surfaces cross-session prior resolutions for the same rule from other sessions in the same workspace. This means the agent sees how that rule was resolved before, by whom, and under what rationale — without a manual memory query. `ck_context` exposes a separate workspace-wide precedent channel distinct from session-scoped memory hits.

## Review Gates
Agent plans (`ck_review_submit`) require human approval (`ck_review_feedback`) before large-scale execution. The agent polls `ck_review_status` rather than blindly proceeding. Review tools expose `browser_url`, `review_url`, `approval_instructions` (with CLI fallback commands), and `review_roles` so humans always know where and how to act.

For OpenCode, the `controlkeel-governance.ts` plugin injects a `submit_plan` tool that replaces default plan exit with a CK-governed review flow. The agent is instructed: "Do not proceed with implementation until ControlKeel approves the plan."

## Cost Governance
Budgets form another layer of bounded autonomy. Agents are assigned specific limits (tokens, API calls, time). `ck_budget` returns `allowed: false` when projected spend exceeds session or daily limits. If an agent burns budget unproductively, a budget circuit-breaker trips, emitting a finding, recording a budget memory record, and pausing the run.

## Hook Enforcement
ControlKeel hooks are the enforcement layer between the agent host and the shell or filesystem. The same rules apply on every host: a hook either gates an action or reports a change, and otherwise stays silent.

| Hook | Hosts | What it does |
| --- | --- | --- |
| **Shell gate** | Claude Code, Codex, Cursor, Copilot, Antigravity, Devin terminal | Plain read-only commands (`ls`, `cat`, `git status`, …) skip validation. Other commands run `ck_validate --kind shell`: a block **denies** the command, a warning goes to the agent as context, and an unreachable ControlKeel is mentioned once per session. |
| **Sensitive write check** | Claude Code, Cursor | Writes to `.env`, keys, certificates and credential files are validated; a block **denies** the write, otherwise the agent gets a note. It never asks the person for permission. |
| **Prompt secret check** | Claude Code, Codex, Devin terminal | Blocks prompts that contain AWS keys, API keys, or private keys. No CLI call. |
| **Stop** | Claude Code, Codex, Cursor, Antigravity, Devin terminal | Reads the project's blocked-finding count. It never blocks the turn and speaks only when the count rises in that session; on Cursor that is a single follow-up. |
| **Pre/PostCompact** | Claude Code | Preserves the active gate and reloads governance after compaction. |
| **Plan review** | Claude Code (ExitPlanMode), Windsurf (ExitPlanMode) | Routes an exited plan to ControlKeel review. Other hosts submit plans with the `ck_review_submit` tool. |

ControlKeel does not register hooks that repeat static reminders (session start/end, tool batches, subagents, tasks, config changes), gate every MCP call, record findings for routine writes or tool failures, or send every tool call through plan review. Hook state (the last reported count, one-time notices) lives in a private `$XDG_STATE_HOME/controlkeel/hooks` directory.

Attaching again replaces only ControlKeel's own hook entries and merges `hooks.json`, `mcp.json`, `config.toml`, `.roomodes` and similar shared files instead of overwriting them, so user hooks, MCP servers and settings survive. Retired ControlKeel hook files from earlier releases are removed.

## Typed Memory Lifecycle
Memory records are written automatically on every significant lifecycle event and retrieved automatically when context is loaded:

### Write triggers (automatic)
- Session created → brief memory
- Task created/updated/completed/paused/resumed → task memory + checkpoint
- Finding created/approved/rejected/escalated → finding memory + platform event + FindingAuditEvent
- Review submitted/approved/denied → review memory + ReviewAuditEvent + prompt outcome tracking
- Proof bundle generated → proof memory + deploy readiness outcome (deploy_success/deploy_failure)
- Budget warn/block → budget memory
- Regression result → invocation (for proof scoring) + regression memory + test_pass/test_fail outcome
- Security scan (ck_validate) → security_scan_clean/security_scan_found outcome
- All outcomes link back to proof, review, and commit SHA where available

### Retrieval triggers (automatic)
- `ck_context` → `Memory.retrieve_for_task` → ranked memory hits + workspace-wide precedent channel
- `ck_context_pack` → task-fact-driven memory hits
- `ck_validate` → same-rule precedent from prior dispositions across the workspace
- `ck_finding` → same-rule precedent from prior dispositions across the workspace
- Resume packet → memory hits + recent events
- `ck_memory_search` → explicit ranked search

### Store semantics
- **Source-id idempotence:** re-submitting the same `(workspace_id, source_type, source_id)` updates the record instead of duplicating.
- **Visibility scoping:** workspace (default), org (`shared_org_id` required), admin.
- **Retention:** stale transient types (task/checkpoint/budget) archived after 90 days by default; durable evidence types (proof/finding/decision/review/goal/regression) preserved.

## API and Workspace Boundaries
All `/api/v1` endpoints enforce workspace authorization for service-account/cloud mode:
- List endpoints scope by `current_workspace_id(conn)`
- Object/action endpoints call `authorize_session_access`, `authorize_task_access`, or `authorize_workspace_for_conn`
- Memory search/create/archive are workspace-scoped
- Cross-workspace access returns 403 Forbidden

Local unauthenticated mode remains a deliberate single-user passthrough.
