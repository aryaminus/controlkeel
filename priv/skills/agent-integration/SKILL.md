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
5. For Conductor, prefer the Claude Code install path because Conductor documents support for `.mcp.json`, `CLAUDE.md`, and `.claude/commands`.

## Cursor (Rules, Skills, Agents, Hooks, Plugins)

Cursor’s **Settings → Rules, Skills, Subagents** (and related **Commands**, **Hooks**, **Plugins**) align to repo files ControlKeel already generates on `controlkeel attach cursor`:

| Cursor concept | CK attach output | Notes |
| --- | --- | --- |
| **Rules** | `.cursor/rules/controlkeel.mdc` | Always-on governance instructions for the agent. |
| **Skills** | `.cursor/skills/*` plus `.agents/skills/*` | Native Cursor skills tree plus open-standard AgentSkills for import tools. |
| **Commands** | `.cursor/commands/*.md` | Slash-style review / plan / annotate / last flows. |
| **Agents / Subagents** | `.cursor/agents/*.md`, `.cursor/background-agents/*.md` | Governor-style prompts and background workflow guidance; hooks include `subagentStart`. |
| **Hooks** | `.cursor/hooks.json`, `.cursor/hooks/*.sh` | Shell / write / MCP / session / stop gates calling `controlkeel validate` when available. |
| **MCP** | `.cursor/mcp.json` | Stdio MCP; use `${workspaceFolder}` for command paths and `CK_PROJECT_ROOT`. |
| **Plugins** | `.cursor-plugin/` | Distributable bundle (`plugin.json`, mirrored assets, `hooks/hooks.json`, `mcpServers`) for **Plugins → Install** / marketplace-style flows. |

**Install path:** `controlkeel attach cursor` in the governed repo root, then enable the ControlKeel MCP server in Cursor and (if desired) install the generated `.cursor-plugin` from the repo or a release export.

## Additional resources

- [Target matrix](references/target-matrix.md)
