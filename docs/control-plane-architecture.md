# Control Plane Architecture

ControlKeel is architected as the control plane for agent-led software delivery. It sits between coding agents (Claude, Codex, OpenCode, Cursor, etc.) and production, acting as a company brain to coordinate policy gates, findings, proofs, budgets, evals, and durable context.

## The sovereignty claim

A company should be able to switch out a generalist model without losing the company-veteran expertise built into its learning system. ControlKeel passes this test by design: findings, reviews, proofs, memory, skills, and outcome history are plain workspace-scoped rows with no model baked into the learning signal. Swap the model; keep the veteran.

This is the part of your AI stack you keep when you change models. The frontier labs are the swappable layer. ControlKeel is the accumulated judgment that survives the swap.

## Core Stack
- **Phoenix + LiveView:** The core web and local UI layer.
- **Ecto + SQLite:** Embedded datastore for tracking findings, proofs, memory, budgets, and reviews.
- **Req:** For all outbound HTTP requests (proxying, cloud sync).
- **Burrito:** For single-binary distribution via GitHub releases.

## Major Subsystems
- **Agent Integration Layer (`AgentIntegration`, `AdapterRegistry`):** Adapts ControlKeel to 40+ native and headless runtimes (MCP, CLI plugins, Hooks).
- **Governance Engine (`Governance`, `FastPath`):** Evaluates diffs, plans, and arbitrary code through the deterministic scanner. Applied through PreToolUse hooks before mutations.
- **Protocol Router (`ControlKeelWeb.Router`):** Exposes MCP, A2A, and internal `/api/v1` routes with workspace-scoped authorization.
- **Typed Memory (`Memory`, `Memory.Store`):** Workspace/org-scoped, source-id idempotent, visibility-validated records with FTS + semantic retrieval.
- **Decision Lineage (`ReviewAuditEvent`, `FindingAuditEvent`, `Policy.Snapshot`):** Every review and finding disposition writes an append-only audit row with actor identity, rationale, and previous/new status. Policy and artifact identity (packs hash, content SHA256) is stamped at decision time so historical decisions can be replayed against the ruleset and content that governed them, not current mutable state.
- **Precedent Retrieval (`Precedent`):** Surfaces cross-session, workspace-wide prior resolutions for the same rule at decision time. When a scanner fires or a finding is filed, the agent sees how that rule was resolved before, by whom, and under what rationale — without a manual query.
- **Outcome Tracker (`Learning.OutcomeTracker`):** Auto-emits deploy readiness, security scan, regression, and prompt-approval outcomes to typed memory with metadata linking back to the shipping decision. Feeds the router weight computation and agent leaderboards.
- **Observability Cockpit:** Reconstructs agent sessions and provides human-gated regression loop mechanisms. Benchmark runs automatically close or reopen the originating eval candidates based on results.
- **Cloud Sync (`Cloud.Sync`, `Cloud.SyncEngine`):** Dormant-until-configured bidirectional sync for findings, reviews, digests, and memory records. Token-authenticated, workspace-scoped, redacted before egress, idempotent by external_id.
- **Hook Enforcement:** PreToolUse hooks deny blocked shell/file operations; PostToolUse hooks nudge based on validation decisions; UserPromptSubmit hooks check blocked findings and budget pressure.

## How the loop compounds

The learning loop is the asset. Each pass through the loop makes the next decision better-informed:

1. **Decision** — a scanner fires, a review is approved, a finding is disposed. The decision writes an immutable audit row with policy/artifact/model snapshots.
2. **Outcome** — deploy readiness, security scan, and regression results auto-emit outcomes linked back to the decision that shipped the change.
3. **Evaluation** — recurring failure patterns cluster into eval candidates. Benchmark drafts use bounded real trace evidence, not paraphrases.
4. **Closure** — benchmark run results automatically archive (all matched) or reopen (any miss) the originating eval candidate, closing the feedback loop.
5. **Precedent** — when the same rule fires again, the prior resolution is surfaced in-path, so the agent (or human) does not re-derive the same edge case.

This is what makes ControlKeel a hill-climbing machine rather than a logbook: every decision generates outcome signal, every outcome feeds evaluation, and every evaluation becomes searchable precedent for the next decision.

## Enforcement model
| Layer | Enforcement | Surface |
| --- | --- | --- |
| Scanner (FastPath) | Hard block via PreToolUse hook | Shell commands, sensitive file writes, secrets in prompts |
| Task completion gate | `{:error, :unresolved_findings}` | Mission.complete_task |
| Budget gate | `allowed: false` | Budget.estimate/commit |
| Review gate | Platform worker blocks execution | Platform.run_task |
| API workspace scope | 403 Forbidden | All /api/v1 object/action endpoints |
| Cloud sync scope | 403 Forbidden | CloudSyncController push/pull |

## Deployment Models
- **Local:** Runs as a CLI daemon on the developer's laptop (`controlkeel setup`). Single-user passthrough when unauthenticated.
- **Cloud/Self-Hosted:** Hosted control plane for distributed teams, accepting telemetry and proofs from local nodes. Service-account workspace scoping enforced on all API endpoints.
