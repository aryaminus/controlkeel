# ControlKeel Agent Integrations

This is the current ControlKeel distribution and attachment matrix.

## Install ControlKeel

ControlKeel itself is distributed through GitHub Releases, with convenience install channels layered on top:

```bash
brew tap aryaminus/controlkeel && brew install controlkeel
npm i -g @aryaminus/controlkeel
echo "@aryaminus:registry=https://npm.pkg.github.com" >> ~/.npmrc
echo "//npm.pkg.github.com/:_authToken=YOUR_GITHUB_CLASSIC_PAT" >> ~/.npmrc
npm i -g @aryaminus/controlkeel --registry=https://npm.pkg.github.com
curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh
irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex
```

Tagged releases publish the packaged binaries, checksum manifest, installer scripts, and the portable plugin bundles described below.
The GitHub Packages npm path is for the bootstrap installer only and requires a GitHub personal access token (classic) for local installs.

## Native-first agents

These clients get MCP plus a native companion install by default when you run `controlkeel attach ...`.
On a clean repo, `attach` also auto-bootstraps the governed project binding by default.

| Agent | Attach command | Native companion | Exportable bundles |
|---|---|---|---|
| Claude Code | `controlkeel attach claude-code` | Installs `.claude/skills` and `.claude/agents` | `claude-standalone`, `claude-plugin` |
| Codex CLI | `controlkeel attach codex-cli` | Installs `.agents/skills` and `.codex/agents` | `codex`, `open-standard` |
| VS Code | `controlkeel attach vscode` | Writes `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` | `github-repo`, `copilot-plugin` |
| GitHub Copilot | `controlkeel attach copilot` | Writes `.github/skills`, `.github/agents`, `.github/mcp.json`, `.vscode/mcp.json` | `github-repo`, `copilot-plugin` |

## MCP plus instructions agents

These clients still attach through MCP, but the native companion is an instructions bundle under `controlkeel/dist/instructions-only`.

| Agent | Attach command |
|---|---|
| Cursor | `controlkeel attach cursor` |
| Windsurf | `controlkeel attach windsurf` |
| Kiro | `controlkeel attach kiro` |
| Amp | `controlkeel attach amp` |
| OpenCode | `controlkeel attach opencode` |
| Gemini CLI | `controlkeel attach gemini-cli` |
| Continue | `controlkeel attach continue` |
| Aider | `controlkeel attach aider` |

Attach flag behavior:

- `--mcp-only` keeps attachment to MCP only
- `--no-native` skips native skills or bundle generation
- `--scope user|project` applies to targets that support both install locations

## Provider access

ControlKeel does not assume it can use an opaque agent subscription. Provider access resolves in this order:

1. supported agent bridge
2. workspace or service-account profile
3. user default provider profile
4. project override
5. local Ollama
6. heuristic fallback

Today, the documented bridge path is environment-based for supported clients:

- Claude Code -> Anthropic-compatible environment
- Codex CLI -> OpenAI-compatible environment

If no bridge, CK-owned profile, or local model is available, agents can still use ControlKeel for governance, MCP tools, proofs, skills, and benchmarks without human setup. Model-backed features fall back to heuristics or return explicit capability guidance.

## Skills and plugin commands

List and validate the skill catalog:

```bash
controlkeel skills list
controlkeel skills validate
controlkeel skills doctor
```

Export publishable bundles:

```bash
controlkeel skills export --target claude-plugin
controlkeel skills export --target copilot-plugin
controlkeel skills export --target codex
controlkeel skills export --target open-standard
```

Install a native target without using `attach`:

```bash
controlkeel skills install --target claude-standalone --scope user
controlkeel skills install --target codex --scope user
controlkeel skills install --target github-repo --scope project
```

## Dist output locations

Exported bundles are written under:

- `controlkeel/dist/claude-plugin/`
- `controlkeel/dist/copilot-plugin/`
- `controlkeel/dist/codex/`
- `controlkeel/dist/open-standard/`
- `controlkeel/dist/instructions-only/`

Published release bundles use the same target set, but ship as release assets:

- `controlkeel-claude-plugin.tar.gz`
- `controlkeel-copilot-plugin.tar.gz`
- `controlkeel-codex.tar.gz`
- `controlkeel-open-standard.tar.gz`
- `controlkeel-instructions-only.tar.gz`

## MCP tool surface

Core runtime tools:

- `ck_validate`
- `ck_context`
- `ck_finding`
- `ck_budget`
- `ck_route`

Skill discovery tools are exposed when the catalog is not empty:

- `ck_skill_list`
- `ck_skill_load`

## Canonical source of truth

- Built-in skills live in `priv/skills/`
- Generated native bundles are derived from that catalog
- `/skills` in the web UI shows validation diagnostics, export/install actions, and the live compatibility matrix
