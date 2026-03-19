---
name: proof-memory
description: "Use ControlKeel proof bundles, typed memory, and resume packets before closing or resuming work. Activate this when you need durable evidence or historical context."
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
---

# Proof and Memory Skill

Use this skill when you need the durable system-of-record view instead of only the live session state.

## Workflow

1. Call `ck_context`.
2. Review `proof_summary`, `memory_hits`, and `resume_packet`.
3. Use the proof bundle to understand deploy readiness, open findings, and rollback expectations.
4. Use memory hits to avoid repeating prior decisions or losing domain constraints.

## Additional resources

- [Proof workflow](references/proof-workflow.md)

