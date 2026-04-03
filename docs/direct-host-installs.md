# Direct Host Installs

This document answers a narrower question than the main support matrix:

**If a user wants to install the ControlKeel companion directly into the host, what is the strongest real path available today?**

ControlKeel keeps `controlkeel attach <host>` as the safest default because it installs the full governed repo-local experience. But several hosts now also have stronger direct-install paths.

## Published package or extension installs

| Host | Direct install | Notes |
| --- | --- | --- |
| OpenCode | Add `"plugin": ["@aryaminus/controlkeel-opencode"]` to `opencode.json` | Publishes the npm plugin entrypoint. Use `controlkeel attach opencode` as well for repo-local commands, agents, and MCP config. |
| Pi | `pi install npm:@aryaminus/controlkeel-pi-extension` | For Pi builds that support npm-backed extension installs. |
| Pi | `pi -e npm:@aryaminus/controlkeel-pi-extension` | Short form of the same Pi extension flow. |
| VS Code | `code --install-extension controlkeel-vscode-companion.vsix` | Installs the CK browser-review companion from a packaged VSIX. |
| Gemini CLI | `gemini extensions link ./controlkeel/dist/gemini-cli-native` | Direct extension-link flow for the exported Gemini companion bundle. |
| Augment / Auggie CLI | `npm install -g @augmentcode/auggie` | Installs the host CLI so CK’s Augment-native workspace bundle and plugin bundle can be used locally. |

## Direct local plugin or bundle installs

| Host | Direct install | Notes |
| --- | --- | --- |
| Claude Code | `controlkeel plugin install claude` | Installs the local Claude plugin bundle with hooks, MCP config, and command prompts. |
| Claude Code | `claude --plugin-dir ./controlkeel/dist/claude-plugin` | Local plugin-dir install for the exported Claude plugin bundle, including `/controlkeel-review`, `/controlkeel-annotate`, and `/controlkeel-last`. |
| GitHub Copilot | `controlkeel plugin install copilot` | Installs the local Copilot plugin bundle and hooks into the project, plus `/controlkeel-review`, `/controlkeel-annotate`, and `/controlkeel-last`. |
| Codex CLI | `controlkeel plugin install codex` | Installs the local Codex plugin bundle and marketplace manifest, including `/controlkeel-review`, `/controlkeel-annotate`, and `/controlkeel-last`. |
| Augment / Auggie CLI | `auggie --plugin-dir ./controlkeel/dist/augment-plugin` | Loads the local Augment plugin bundle with hook-native review interception, MCP, rules, subagent, and command prompts. Export it first or use the release artifact. |
| Amp | `amp skill add ./controlkeel/dist/amp-native/.agents/skills/controlkeel-governance` | Installs the native CK skill bundle directly into Amp. Use alongside the exported `.amp/plugins/` directory when you want event hooks and custom tools too. |
| OpenClaw | `controlkeel plugin install openclaw` | Installs the local OpenClaw plugin bundle and MCP manifest. |

## Attach-first native installs

These hosts now ship richer hook, command, workflow, or config surfaces, but the truthful install path is still `controlkeel attach <host>`:

| Host | Direct install path today |
| --- | --- |
| Windsurf | `controlkeel attach windsurf` |
| Continue | `controlkeel attach continue` |
| Cline | `controlkeel attach cline` |
| Goose | `controlkeel attach goose` |
| Kiro | `controlkeel attach kiro` |
| Augment / Auggie CLI | `controlkeel attach augment` |
| Cursor | `controlkeel attach cursor` |
| Roo Code | `controlkeel attach roo-code` |
| Aider | `controlkeel attach aider` |
| Hermes Agent | `controlkeel attach hermes-agent` |
| OpenClaw | `controlkeel attach openclaw` |
| Factory Droid | `controlkeel attach droid` |
| Forge | `controlkeel attach forge` |

## Why some hosts stay attach-first

Some hosts expose hooks, workflows, rules, or repo-local command surfaces but do not expose a stable package marketplace or npm extension flow that CK can truthfully claim today.

For those hosts, CK now installs stronger native assets than before:

- Windsurf: hooks, canonical `hooks.json`, workflows, commands, MCP config
- Continue: prompts, command prompts, headless review prompts, MCP server config
- Cline: hooks, commands, rules, workflows
- Goose: commands, workflow recipes, extension YAML
- Kiro: hooks, steering, tool policy settings, commands
- Augment / Auggie CLI: workspace commands, subagents, rules, MCP config, local plugin hooks, and ACP-compatible runtime transport
- Amp: plugin scaffold, native skill bundle, and commands
- Cursor: commands, background-agent guidance, rules
- Roo Code: commands, guidance, `.roomodes`
- Aider: command-driven review snippets and config

That is a real improvement in host usability, but it is not the same thing as a published marketplace package.

Across the command-capable bundles, CK now standardizes the agent-facing command loop as much as the host format allows:

- `review`
- `submit-plan`
- `annotate`
- `last`

That matters because CK is intended to be agent-operated first: the host should be able to call into ControlKeel directly for plan approval, focused annotation, and review reopening without requiring the human to manually reconstruct the flow.

## Release and publish truth

Current release automation now supports:

- npm publication for the main CK bootstrap package
- npm publication for the OpenCode package
- npm publication for the Pi package
- `.vsix` packaging for the VS Code companion
- conditional VS Code marketplace publication when `VSCE_PAT` is configured

Hosts without a documented published package flow remain attach-first in the docs and `/skills`.

## Update behavior after a new CK release

ControlKeel does not silently rewrite repo files or host plugin directories when a new release ships.

- Upgrading the main `controlkeel` binary through Homebrew, npm bootstrap, or the release installers updates the CLI itself.
- MCP registrations that call `controlkeel` directly, or call the generated `controlkeel-mcp` wrapper, start using the new binary automatically on the next host invocation.
- CK now auto-syncs stale attached bundles on the next governed CLI load when the attachment has a real install target and scope. In practice, repo-local and user-scope `controlkeel attach <host>` installs can self-heal to the current CK version.
- Some artifacts still do not auto-refresh. That includes exported tarballs, local `--plugin-dir` installs, manually copied plugin directories, and sideloaded `.vsix` files.
- Refresh those by rerunning `controlkeel attach <host>` or the relevant `controlkeel skills install` / `controlkeel plugin export` flow.
- Published host packages follow the host package manager:
  - OpenCode / Pi npm packages update through npm or the host’s extension updater.
  - VS Code marketplace installs can auto-update through VS Code itself; sideloaded `.vsix` installs still require a newer package to be installed.
  - Local `--plugin-dir` installs do not auto-update; rebuild or reinstall the bundle.

## Remote and browser behavior

CK also pulls a few practical host patterns from Plannotator for direct-install flows:

- `CONTROLKEEL_REMOTE=1`: treat the current environment as remote or forwarded; CK will avoid trying to auto-open a browser and will return the review URL instead.
- `CONTROLKEEL_BROWSER=/path/to/browser` or `BROWSER=...`: force a specific browser command for `controlkeel review plan open`.
- `CONTROLKEEL_REVIEW_EMBED=vscode_webview`: prefer the VS Code companion embed path instead of an external browser.
- `CONTROLKEEL_AUTO_OPEN_REVIEWS=0`: disable automatic browser launching entirely. Test runs already default to this behavior.
