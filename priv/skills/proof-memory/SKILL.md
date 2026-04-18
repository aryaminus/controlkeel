---
name: proof-memory
description: "Use ControlKeel proof bundles, typed memory, workspace snapshots, transcript summaries, and resume packets before closing or resuming work. Activate this when you need durable evidence or historical context."
when_to_use: "Activate before closing a session, resuming previous work, or when the user says 'remember this', 'save proof', 'snapshot state', or references prior decisions."
argument-hint: "[checkpoint label or context to preserve]"
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
  version: "2.0"
  category: proof
  ck_mcp_tools:
    - ck_context
    - ck_memory_search
    - ck_memory_record
    - ck_memory_archive
    - ck_regression_result
---

# Proof and Memory Skill

Use this skill when you need the durable system-of-record view instead of only the live session state.

## Workflow

1. Call `ck_context`.
2. Review `proof_summary`, `memory_hits`, `workspace_context`, `context_reacquisition`, `instruction_hierarchy`, `recent_events`, and `resume_packet`.
3. Use the proof bundle to understand deploy readiness, regression evidence, open findings, and rollback expectations.
4. Use `ck_memory_search` when prior decisions, checkpoints, or findings need explicit retrieval instead of relying only on passive memory hits.
5. Use `ck_memory_record` to preserve new decisions or operator intent that future agents should recover explicitly.
6. Use `ck_memory_archive` to retire stale or superseded memories so retrieval quality does not decay.

## Additional resources

- [Proof workflow](references/proof-workflow.md)
