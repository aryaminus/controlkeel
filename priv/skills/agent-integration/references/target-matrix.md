# Target Matrix

## Native-first

- Codex: `.agents/skills`, `.codex/agents`
- Claude Code: `.claude/skills`, `.claude/agents`, plugins
- Copilot / VS Code: `.github/skills`, `.github/agents`, plugins
- Cursor: `.cursor/skills`, `.cursor/agents`, `.cursor/rules`, `.cursor/hooks.json`, `.cursor/mcp.json`, `.cursor-plugin/`
- OpenCode: `.opencode/skills` and `.agents/skills`
- Augment: `.augment/skills`
- Kilo: `.kilo/skills`
- Devin for Terminal: `.devin/skills` (project), `~/.config/devin/skills` (user)
- Warp: `.warp/skills` and `.agents/skills`
- Conductor compatibility: use Claude Code repo-local surfaces (`.mcp.json`, `CLAUDE.md`, `.claude/commands`)

## MCP-only fallback

- Windsurf (native rules/workflows/hooks; AgentSkills compatibility via `.agents/skills`)
- Kiro
- Amp
- Gemini CLI
- Continue
- Aider

All MCP-only tools should still receive CK instruction snippets so the model knows how and when to call CK tools.

## Scope and distribution boundaries

- Project scope writes into the governed repository. User scope writes host-level files only when the target advertises user support; project binding and evidence remain project-specific.
- `ck_attach` always authorizes an existing canonical project inside `CK_PROJECT_ROOT`, regardless of scope. Scope changes artifact destinations, not which project may be attached.
- Some hosts keep MCP registration in a user-managed config even when companion artifacts are project-scoped. Current examples include Cursor, Windsurf, Kiro, Kilo, Amp, Augment, OpenCode, Gemini CLI, Cline, Continue, and Goose. Their attach output identifies the exact host config path before restart; this host registration is separate from project-root authorization.
- Local stdio MCP exposes the full local catalog. Hosted MCP is a separate service-account OAuth surface with a narrower scope-authorized catalog; consult `docs/support-matrix.md` for exact tool availability.
- Exported plugin directories and marketplace manifests are release/install bundles. They are not evidence that a host's public marketplace has published or approved ControlKeel.
- `github.com/.../releases/latest/download/...` selects a versioned release asset. `raw.githubusercontent.com/.../main/...` reads mutable default-branch content.
