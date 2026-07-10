---
name: agent-integration
description: "Attach ControlKeel to agents, verify MCP connectivity, confirm native skills availability, and choose the right distribution target for each client."
when_to_use: "Activate when setting up CK with a new agent, installing the plugin, configuring MCP, or when the user asks how to attach ControlKeel to their tool."
argument-hint: "[agent name or tool to integrate]"
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
  - gemini-cli-native
  - kiro-native
  - kilo-native
  - amp-native
  - augment-native
  - hermes-native
  - multica-native
  - openclaw-native
  - devin-terminal-native
  - warp-native
  - droid-bundle
  - forge-acp
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
6. Treat the target matrix as the discovery contract: every listed native skill directory is scanned by the registry, while host-specific non-skill companions remain documented separately.
7. For `ck_attach`, validate the canonical project inside `CK_PROJECT_ROOT` for every scope. User scope changes native destinations but does not authorize another project; consult the target matrix for hosts whose MCP registration also updates a user-managed config path.
8. Run the complete verification path after install: `controlkeel setup`, `controlkeel attach <host>`, `controlkeel attach doctor`, `controlkeel provider doctor`, `controlkeel status`, and `controlkeel findings`.
9. Keep boundaries explicit: project attach mutates the governed repo; user scope is valid only for targets that advertise it and writes user-level host files. Local stdio MCP has the full local tool set, while hosted MCP is a narrower OAuth-scoped set.
10. Describe exported plugin and marketplace manifests as installable bundles, not as proof that a public marketplace has published or approved them.

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

**Install path:** run `controlkeel setup` and `controlkeel attach cursor` in the governed repo root, then enable the local ControlKeel MCP server in Cursor and (if desired) install the generated `.cursor-plugin` from the repo or a release export. The generated marketplace-style bundle is not itself a public marketplace listing. Finish with `controlkeel attach doctor`, `controlkeel provider doctor`, `controlkeel status`, and `controlkeel findings`.

## Additional resources

- [Target matrix](references/target-matrix.md)
