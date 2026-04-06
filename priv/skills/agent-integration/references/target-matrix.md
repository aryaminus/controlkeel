# Target Matrix

## Native-first

- Codex: `.agents/skills`, `.codex/agents`
- Claude Code: `.claude/skills`, `.claude/agents`, plugins
- Copilot / VS Code: `.github/skills`, `.github/agents`, plugins
- Conductor compatibility: use Claude Code repo-local surfaces (`.mcp.json`, `CLAUDE.md`, `.claude/commands`)

## MCP-only fallback

- Cursor
- Windsurf
- Kiro
- Amp
- OpenCode
- Gemini CLI
- Continue
- Aider

All MCP-only tools should still receive CK instruction snippets so the model knows how and when to call CK tools.
