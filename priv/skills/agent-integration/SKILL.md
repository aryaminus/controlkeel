---
name: agent-integration
description: "Attach ControlKeel to agents, verify MCP connectivity, confirm native skills availability, and choose the right distribution target for each client."
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
disable-model-invocation: true
metadata:
  author: controlkeel
  version: "2.0"
  category: integration
---

# Agent Integration Skill

Use this skill when the task is attaching or distributing ControlKeel across agents.

## Workflow

1. Identify whether the target is native-skill capable, plugin-capable, or MCP-only.
2. Prefer native install where supported, with CK MCP as the transport for governance tools.
3. Export plugin bundles when the user wants a shareable package.
4. For MCP-only tools, generate the instruction bundle and installation guidance.

## Additional resources

- [Target matrix](references/target-matrix.md)

