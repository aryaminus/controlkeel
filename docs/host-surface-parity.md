# Host Surface Parity

This document turns the April 2, 2026 host audit into an implementation map for ControlKeel.

The goal is not to clone Plannotator's product. The goal is to make ControlKeel use the strongest official host surface each agent actually exposes, then describe that support truthfully in `/skills`, the API, release assets, and docs.

## Principles

- Use the strongest official surface the host exposes.
- Prefer agent-owned auth and subscriptions over duplicate ControlKeel API keys when the host can already drive models.
- Keep ControlKeel as the governance and review authority.
- Do not claim hook-native or runtime-native support unless CK actually installs or uses that surface.
- Keep marketplace and direct-plugin installs separate from local export bundles until the package is genuinely publishable.

## Capability classes

ControlKeel now groups host support by real install and control surfaces:

- Hook-native
  - Claude Code
  - Copilot
  - Windsurf
  - Cline
  - Kiro
- Plugin-native
  - OpenCode
  - Amp
- File-plan-mode
  - Pi
- Prompt or command-native
  - Continue
  - Gemini CLI
  - Goose
  - Roo Code
- Browser or embed companion
  - VS Code
- Review-only or command-driven
  - Codex CLI
  - Aider

## Broad host rollout

The broad parity pass focused on hosts where official docs expose more than a static instructions file.

### Windsurf

Official surfaces used:

- Cascade hooks
- MCP config
- workflows
- repo rules

What CK now exports:

- `.windsurf/rules`
- `.windsurf/commands`
- `.windsurf/workflows`
- `.windsurf/hooks`
- `.windsurf/mcp.json`

Why this matters:

- CK can now surface plan-review entry points through real Windsurf companions instead of treating Windsurf as rules-only.

### Continue

Official surfaces used:

- prompt system
- slash or command prompts
- headless CLI workflows
- MCP server config

What CK now exports:

- `.continue/prompts`
- `.continue/commands`
- `.continue/mcpServers/controlkeel.yaml`

Why this matters:

- Continue users now get explicit plan and review prompts plus a headless review flow, instead of only a generic skill bundle.

### Cline

Official surfaces used:

- hooks
- commands
- rules
- skills
- workflow guidance

What CK now exports:

- `.cline/skills`
- `.cline/commands`
- `.cline/hooks`
- `.clinerules`

Why this matters:

- CK can now intercept review moments through Cline-native command and hook artifacts instead of relying on passive instructions only.

### Goose

Official surfaces used:

- MCP extension registration
- recipes
- command flows
- `.goosehints`

What CK now exports:

- `.goosehints`
- `goose/workflow_recipes`
- `goose/commands`

Why this matters:

- Goose users now get command-driven review helpers and recipe-style governance paths alongside MCP registration.

### Kiro

Official surfaces used:

- hooks
- steering files
- tool policy and controls
- command guidance

What CK now exports:

- `.kiro/hooks`
- `.kiro/steering`
- `.kiro/settings`
- `.kiro/commands`
- `.kiro/mcp.json`

Why this matters:

- CK can now scope review and tool policy in Kiro more explicitly instead of stopping at a single hook file.

### Amp

Official surfaces used:

- plugin API
- event hooks
- custom tools
- command palette commands

What CK now exports:

- `.amp/plugins/controlkeel`
- `.amp/commands`
- `.amp/package.json`

Why this matters:

- Amp is now modeled as a plugin-native target rather than a loose file drop.

### Gemini CLI

Official surfaces used:

- extension manifest
- command packages
- agent skills
- `GEMINI.md` context

What CK now exports:

- `gemini-extension.json`
- `.gemini/commands/controlkeel`
- `skills/controlkeel-governance`
- `GEMINI.md`
- extension `README.md`

Why this matters:

- CK no longer treats `GEMINI.md` as the whole story and now ships actual command surfaces too.

### Cursor

Official surfaces used (as documented by Cursor for IDE-native agent features):

- **Rules** — repo-scoped guidance (for example `.mdc` under `.cursor/rules`)
- **Skills** — Agent Skills under `.cursor/skills`
- **Commands** — slash/recipe-style command markdown under `.cursor/commands`
- **Agents** — specialized agent prompt files under `.cursor/agents` (including background-style workflows)
- **Hooks** — workspace `hooks.json` plus executable hook scripts (session, shell, tool, MCP, subagent gates)
- **MCP** — project `mcp.json` wiring for stdio servers
- **Plugins** — distributable plugin bundles (manifest + mirrored assets + plugin-local hooks)

What CK now exports:

- `.cursor/rules/controlkeel.mdc`
- `.cursor/skills/*` (mirrors governed CK skills for Cursor-native discovery)
- `.cursor/commands/*` (review, submit-plan, annotate, last, and related flows)
- `.cursor/agents/controlkeel-governor.md`
- `.cursor/background-agents/controlkeel.md`
- `.cursor/hooks.json` and `.cursor/hooks/*.sh` (governance gates; includes `subagentStart`)
- `.cursor/mcp.json` (stdio MCP; portable `${workspaceFolder}` launcher where applicable)
- `.agents/skills/*` (open-standard AgentSkills tree; many hosts and import flows read this)
- `.cursor-plugin/` — installable plugin bundle: `plugin.json`, mirrored `rules/`, `skills/`, `agents/`, `commands/`, `hooks/hooks.json`, and `mcpServers`
- `AGENTS.md` — portable instruction layer for hosts that read repo root guidance

Why this matters:

- Cursor’s **Rules / Skills / Commands / Agents / Hooks / Plugins** settings map directly to the files above. CK keeps them consistent so operators can use **attach**, **skills.sh**, or **imported plugin** flows without hand-maintaining parallel copies.

### Roo Code

Official surfaces used:

- repo rules
- commands
- cloud-agent guidance
- `.roomodes`

What CK now exports:

- `.roo/skills`
- `.roo/rules`
- `.roo/commands`
- `.roo/guidance`
- `.roomodes`

Why this matters:

- Roo gets a stronger command and mode surface without inventing unsupported runtime claims.

### Aider

Official surfaces used:

- command-driven chat flows
- config files
- repo instructions

What CK now exports:

- `AIDER.md`
- `.aider.conf.yml`
- `.aider/commands`
- shared repo instructions

Why this matters:

- Aider remains command-driven and truthful. CK now gives it a better governed review surface without pretending it has hooks, plugins, or native MCP SDK support.

## Support truth

The broad matrix follows these rules:

- Hook-native means CK installs or uses actual host hook surfaces.
- Plugin-native means CK installs or exports actual plugin artifacts, not only markdown instructions.
- Prompt or command-native means the host has real prompt, command, or recipe surfaces CK can install directly.
- Browser or embed companion means CK augments review UX but is not the host runtime.
- Review-only means CK can govern review moments but does not claim host-side planning interception.

## Remaining gap

Direct marketplace or npm installs are still a separate track.

Today, the broad matrix primarily supports:

- `controlkeel attach <host>`
- exported native bundles under `controlkeel/dist/*`
- repo-local command, hook, workflow, rule, or plugin assets

Not every host is yet published as a marketplace plugin or npm-installable package. CK should not claim that until the package metadata, publishing workflow, and install command are all real.

The current direct-install truth table lives in [direct-host-installs.md](direct-host-installs.md).

## Validation

When adding or changing a host surface:

- update the exporter output
- update the installer output when the host supports direct attach
- update `AgentIntegration` metadata
- update `/skills` and API payload expectations
- update docs
- add file-level tests for the exported artifacts
- run `mix precommit`
