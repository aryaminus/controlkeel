# Control Plane Claim Matrix

This matrix keeps README claims tied to implementation and tests. Use it when
changing findings, sessions, proofs, memory, cloud sync, benchmarking, or
observability logic.

| Claim area | Current contract | Evidence |
| --- | --- | --- |
| Local governance | Local CLI/MCP can create sessions, findings, reviews, proof bundles, budget records, and typed memory without a provider key. | `test/controlkeel/mission_test.exs`, `test/controlkeel/mcp/tools/ck_memory_tools_test.exs`, `test/controlkeel_web/controllers/api_controller_test.exs` |
| Project/workspace boundaries | Service-account API access is scoped to one workspace for list and object/action endpoints. Local unauthenticated mode remains a deliberate single-user passthrough. | `test/controlkeel_web/controllers/api_scope_test.exs` |
| Typed memory and learning | Memory records are workspace-scoped by default, can be org/admin visible when explicitly marked, and update idempotently when `source_id` is stable. | `test/controlkeel/memory_test.exs`, `test/controlkeel/memory/shared_memory_test.exs`, `test/controlkeel/mcp/tools/ck_memory_tools_test.exs` |
| Proof and regression evidence | External regression results are stored as invocations for proof scoring and as `regression` memory records for future retrieval. | `test/controlkeel/mission_test.exs` |
| Cloud evidence sync | Push/pull is token-authenticated, workspace-scoped, redacted before egress, and idempotent for findings, reviews, digests, and memory records. | `test/controlkeel_web/controllers/cloud_sync_controller_test.exs`, `test/controlkeel/cloud/sync_engine_test.exs` |
| Observability learning loop | Observability derives eval candidates, stores them idempotently, creates human-gated benchmark drafts, materializes approved drafts, and requires explicit execution before benchmark runs. | `test/controlkeel/observability_test.exs`, `test/controlkeel_web/live/observability_*_test.exs` |
| Benchmark claims | Public benchmark claims must name suite, subject, scorer, scenario count, false-positive baseline, and cost/latency source. | `docs/benchmarks.md`, `test/controlkeel/benchmark_test.exs` |
| Human gates | Plan/diff/completion reviews expose browser URLs when available plus fallback CLI commands and role-specific reviewer hints. | `lib/controlkeel/mcp/tools/ck_review_submit.ex`, `lib/controlkeel/mcp/tools/ck_review_status.ex` |
| Decision lineage and replay | Every review and finding disposition writes an append-only audit row (`ReviewAuditEvent`, `FindingAuditEvent`) with actor identity, rationale, and previous/new status. Policy and artifact identity is stamped at decision time via `Policy.Snapshot` so historical decisions replay against decision-time state, not current mutable state. | `test/controlkeel/accounts_review_test.exs`, `test/controlkeel/mission_test.exs` |
| Outcome auto-emission | Deploy readiness, security scan, regression, and prompt-approval outcomes auto-emit to `OutcomeTracker` with metadata linking back to the shipping decision. Regression outcomes link proof, review, and commit SHA. | `test/controlkeel/mission_test.exs`, `test/controlkeel/mcp/tools/ck_validate_test.exs` |
| Precedent retrieval in-path | `ck_validate` and `ck_finding` surface cross-session prior resolutions for the same rule at decision time. `ck_context` exposes a workspace-wide precedent channel separate from session-scoped memory. | `test/controlkeel/mcp/tools/ck_validate_test.exs`, `test/controlkeel/mcp/tools/ck_finding_test.exs`, `test/controlkeel/mcp/tools/ck_context_test.exs` |
| Model provenance | Reviews and findings store `model_provenance` metadata from explicit fields or the latest invocation. Trace and export surfaces provenance so model comparisons are possible on the same private evals. | `test/controlkeel/accounts_review_test.exs`, `test/controlkeel/mission_test.exs` |
| Eval candidate lifecycle closure | Benchmark run results automatically archive (all matched) or reopen (any miss) the originating eval candidate, closing the improvement feedback loop. | `test/controlkeel/observability_test.exs` |
| Skill evolution install | `ck_skill_evolution` supports install mode that materializes generated drafts into `.agents/skills/` under the project root. | `test/controlkeel/mcp/protocol_test.exs` |

## Maintenance rule

If a README claim expands beyond this matrix, add or update a test in the
evidence column before shipping the claim. If behavior is intentionally local
only or advisory, say so in the claim rather than implying cloud/org coverage.
