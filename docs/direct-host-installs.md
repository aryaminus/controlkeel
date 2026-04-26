# Direct Host Installs

This document answers a narrower question than the main support matrix:

**If a user wants to install the ControlKeel companion directly into the host, what is the strongest real path available today?**

If you are orienting across the whole documentation set first, start with [README.md](README.md).

ControlKeel keeps `controlkeel attach <host>` as the safest default because it installs the full governed repo-local experience. But several hosts now also have stronger direct-install paths.

The published host-facing npm companions currently are:

- OpenCode companion: [`@aryaminus/controlkeel-opencode`](https://www.npmjs.com/package/@aryaminus/controlkeel-opencode)
- Pi extension: [`@aryaminus/controlkeel-pi-extension`](https://www.npmjs.com/package/@aryaminus/controlkeel-pi-extension)

This page owns the exact host-facing package names and install commands. The main CLI bootstrap package stays documented in the root [README](../README.md).

## Skills.sh / AgentSkills installs

ControlKeel's built-in skills are already installable through the public [skills.sh](https://skills.sh/) CLI and registry flow.

| Surface | Install |
| --- | --- |
| Whole CK skill collection | `npx skills add https://github.com/aryaminus/controlkeel` |
| Single CK governance skill | `npx skills add https://github.com/aryaminus/controlkeel --skill controlkeel-governance` |

This works today because the `skills` CLI already discovers the CK skill set in this repository. In a local validation run, it found 11 ControlKeel skills and offered installation into universal `.agents/skills` plus supported agent-specific skill directories.

These installs are best understood as **skill-package distribution**, not as proof of a full native CK runtime contract for that host.

Each CK skill bundle still centers on `SKILL.md`, with optional references, scripts, and assets layered around it. The host may discover only the skill metadata first, load the full skill body when relevant, and only then touch bundled helper files if the active workflow needs them. That is the practical progressive-disclosure model CK tries to preserve across native installs, AgentSkills-compatible directories, and MCP skill loading.

Because of that, skill installs should also be treated with normal supply-chain caution:

- CK bundled skills are the reviewed first-party baseline
- team-authored skills should be versioned and reviewed like other automation
- third-party/community skill packages should be inspected before they are allowed to steer high-impact work

## skills.sh agent-name coverage

The [skills.sh](https://skills.sh/) agent list is broader than CK's native attach catalog. Treat those names in three buckets:

- Native CK support already exists:
  `amp`, `claude-code`, `cline`, `codex` via `codex-cli`, `cursor`, `droid`, `gemini` via `gemini-cli`, `copilot`, `goose`, `kiro` / `kiro-cli`, `kilo`, `letta-code`, `opencode`, `roo` / `roo-code`, `vscode`, `windsurf`
- Skills-only compatibility currently exists through the `skills.sh` install path:
  `antigravity`, `clawdbot`, `nous-research`, `trae`
- Not every skills.sh logo implies a native CK MCP/plugin/hook/extension contract.
  For the skills-only names above, CK currently ships open-standard AgentSkills compatibility, not a repo-native attach command.

## Published package or extension installs

| Host | Direct install | Notes |
| --- | --- | --- |
| OpenCode | Add `"plugin": ["@aryaminus/controlkeel-opencode"]` to `opencode.json` | Uses the published npm companion package `@aryaminus/controlkeel-opencode`. Use `controlkeel attach opencode` as well for repo-local commands, agents, skills, and MCP config (`mcp.controlkeel` local command array). |
| Pi | `pi install npm:@aryaminus/controlkeel-pi-extension` | Uses the published npm extension package `@aryaminus/controlkeel-pi-extension` for Pi builds that support npm-backed installs. |
| Pi | `pi -e npm:@aryaminus/controlkeel-pi-extension` | Short form of the same published Pi extension flow. |
| VS Code | `code --install-extension controlkeel-vscode-companion.vsix` | Installs the CK browser-review companion from a packaged VSIX. |
| Gemini CLI | `gemini extensions link ./controlkeel/dist/gemini-cli-native` | Direct extension-link flow for the exported Gemini companion bundle. |
| Augment / Auggie CLI | `npm install -g @augmentcode/auggie` | Installs the host CLI so CK’s Augment-native workspace bundle and plugin bundle can be used locally. |
| Letta Code | `npm install -g @letta-ai/letta-code` | Installs the Letta CLI. Use `controlkeel attach letta-code` after that to add repo-local skills, hooks, and MCP registration helpers. |

## Direct local plugin or bundle installs

| Host | Direct install | Notes |
| --- | --- | --- |
| Claude Code | `controlkeel plugin install claude` | Installs the local Claude plugin bundle with hooks, MCP config, and command prompts. |
| Claude Code | `claude --plugin-dir ./controlkeel/dist/claude-plugin` | Local plugin-dir install for the exported Claude plugin bundle, including `/controlkeel-review`, `/controlkeel-annotate`, and `/controlkeel-last`. |
| GitHub Copilot | `controlkeel plugin install copilot` | Installs the local Copilot plugin bundle and hooks into the project, plus `/controlkeel-review`, `/controlkeel-annotate`, and `/controlkeel-last`. |
| Codex CLI | `controlkeel plugin install codex` | Installs the local Codex plugin bundle and local marketplace manifest, including `/controlkeel-review`, `/controlkeel-annotate`, and `/controlkeel-last`. Project scope writes `plugins/controlkeel` plus `.agents/plugins/marketplace.json`; user scope writes `~/plugins/controlkeel` plus `~/.agents/plugins/marketplace.json`. For native skill loading, `controlkeel attach codex-cli` instead writes `.codex/skills`, `.codex/hooks.json`, `.codex/hooks`, `.codex/agents`, `.codex/commands`, and `.codex/config.toml`. Install Codex itself via `npm install -g @openai/codex` or `brew install --cask codex`, matching the current upstream release channels. Local marketplace registration is not the same thing as being listed in OpenAI's curated Codex plugin catalog, and Codex should be restarted after local plugin or attach changes. |
| Augment / Auggie CLI | `auggie --plugin-dir ./controlkeel/dist/augment-plugin` | Loads the local Augment plugin bundle with hook-native review interception, MCP, rules, subagent, and command prompts. Export it first or use the release artifact. |
| Amp | `amp skill add ./controlkeel/dist/amp-native/.agents/skills/controlkeel-governance` | Installs the native CK skill bundle directly into Amp. Use alongside the exported `.amp/plugins/` directory when you want event hooks and custom tools too. |
| OpenClaw | `controlkeel plugin install openclaw` | Installs the local OpenClaw plugin bundle and MCP manifest. |
| Factory Droid | `controlkeel plugin export droid` | Exports a local Factory plugin bundle with `.factory-plugin/plugin.json`, `skills/`, `commands/`, `droids/`, `hooks/hooks.json`, and `mcp.json`. Install it by adding `./controlkeel/dist/droid-plugin` as a local Droid marketplace, then install `controlkeel@droid-plugin`. |

## Attach-first native installs

These hosts now ship richer hook, command, workflow, or config surfaces, but the truthful install path is still `controlkeel attach <host>`:

| Host | Direct install path today |
| --- | --- |
| Windsurf | `controlkeel attach windsurf` |
| Continue | `controlkeel attach continue` |
| Letta Code | `controlkeel attach letta-code` |
| Cline | `controlkeel attach cline` |
| Goose | `controlkeel attach goose` |
| Kiro | `controlkeel attach kiro` |
| Kilo Code | `controlkeel attach kilo` |
| Augment / Auggie CLI | `controlkeel attach augment` |
| Cursor | `controlkeel attach cursor` |
| Roo Code | `controlkeel attach roo-code` |
| Aider | `controlkeel attach aider` |
| Hermes Agent | `controlkeel attach hermes-agent` |
| OpenClaw | `controlkeel attach openclaw` |
| Forge | `controlkeel attach forge` |

## dmux compatibility

`dmux` is supported as an orchestration adapter, not as a native CK attach target.

Install dmux itself with:

```bash
npm -g i dmux
```

Then attach CK to the underlying agent runtime that dmux will launch inside its worktrees, for example:

```bash
controlkeel attach codex-cli
controlkeel attach claude-code
controlkeel attach opencode
```

dmux-managed worktrees under `.dmux/worktrees/` inherit those repo-local CK surfaces. If you want team-wide governed behavior inside dmux, add hooks such as `.dmux-hooks/worktree_created` and `.dmux-hooks/pre_merge` to run setup or validation before merge.

## Codex-specific note

Codex currently has three distinct CK stories, and mixing them together causes most of the confusion:

1. Native local attach: `controlkeel attach codex-cli`
   This is the strongest day-to-day path when you want `.codex/skills`, `.codex/hooks`, `.codex/agents`, `.codex/commands`, and local MCP wiring. CK now generates multiple Codex custom agents here, including `controlkeel-operator`, `controlkeel-reviewer`, and `controlkeel-docs-researcher`.
2. Local plugin bundle plus local marketplace registration: `controlkeel plugin install codex`
   This writes the plugin bundle and a local marketplace manifest for repo-local or home-local discovery.
3. Curated remote catalog visibility inside Codex product surfaces
   That is a separate distribution track controlled by OpenAI product surfaces, not something CK can force by writing local repo files.

For day-to-day Codex use, there is one more practical guideline:

- keep the repo-local `.codex/*` surface lean
- use CK's native skills and hooks for governed checkpoints, not as a dumping ground for large always-on prose
- prefer on-demand skill loading and focused lifecycle hooks over turning every session into a giant static harness preamble

That keeps CK aligned with its own control-plane posture: minimal stable contracts first, richer capability only when the runtime actually needs it.

Separately, CK now models `codex-app-server` as a real runtime surface for reporting and routing. It still reuses the same local `.codex/` assets, but it is no longer treated as a pure alias in CK's runtime metadata.

Likewise, CK now models `t3code` as a first-class runtime surface (still bootstrapped via `controlkeel attach codex-cli`) so provider-neutral orchestration transport/review semantics are visible in routing and status outputs.

The important practical consequence is that there is still no separate `controlkeel attach codex-app-server` command. If a team is building on top of Codex app-server, the correct CK setup is still `controlkeel attach codex-cli`, because that is what installs the governed `.codex/*` repo surface that app-server-powered clients consume.

If another agent is driving setup on the user's behalf, that agent should still pause for the same Codex checkpoints a human would need to handle: trust the repo if Codex is ignoring project-scoped `.codex/*`, restart Codex after attach or plugin changes, and ask for manual approval if a CK review gate cannot be cleared automatically.

From there the layers split cleanly:

- Codex app-server owns thread lifecycle, approvals, conversation history, and host-side auth/account behavior
- CK owns the governed local MCP, skills, hooks, commands, custom agents, and the review/proof loop attached to that Codex runtime

The same guidance applies when a team is using the Codex SDK rather than talking to Codex only through the terminal UI. The SDK is a programmatic way to drive the local Codex runtime, not a separate CK attach family, so the correct CK setup still begins with `controlkeel attach codex-cli`.

If a user does not see CK in a Codex plugins page, first verify the local install artifacts above before assuming the plugin install failed. Also verify that the repo is trusted, because Codex ignores project-scoped `.codex/` config and hooks for untrusted projects.

## Conductor compatibility

Conductor is not a separate CK attach target, but its own docs make it a real compatibility path because it reuses Claude Code surfaces:

- project MCP config through `.mcp.json`
- project instructions through `CLAUDE.md`
- Claude slash commands through `.claude/commands/`
- isolated per-feature workspaces/branches for parallel agent runs

So the practical CK install path for repositories used in Conductor is:

| Host | Direct install path today |
| --- | --- |
| Conductor | `controlkeel attach claude-code` |

That gives Conductor the CK repo-local MCP wiring and instruction surfaces it already knows how to consume, while keeping the support claim honest: CK is not launching the Conductor app itself.

## Why some hosts stay attach-first

Some hosts expose hooks, workflows, rules, or repo-local command surfaces but do not expose a stable package marketplace or npm extension flow that CK can truthfully claim today.

For those hosts, CK now installs stronger native assets than before:

- Windsurf: hooks, canonical `hooks.json`, workflows, commands, MCP config
- Continue: prompts, command prompts, headless review prompts, MCP server config
- Letta Code: `.agents/skills`, `.letta/settings.json`, `.letta/hooks`, `/mcp add` helper script, and repo-local remote/headless guidance
- Cline: hooks, commands, rules, workflows
- Goose: commands, workflow recipes, extension YAML
- Kiro: hooks, steering, tool policy settings, commands
- Kilo Code: Agent Skills, slash-command workflows, MCP config, and `AGENTS.md`
- Augment / Auggie CLI: workspace commands, subagents, rules, MCP config, local plugin hooks, and ACP-compatible runtime transport
- Amp: plugin scaffold, native skill bundle, and commands
- Cursor: rules, `.cursor/skills`, commands, `.cursor/agents`, background-agent guidance, `hooks.json` + hook scripts, MCP config, and `.cursor-plugin/` export
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

- npm publication for the main CK bootstrap package `@aryaminus/controlkeel`
- npm publication for the OpenCode companion package `@aryaminus/controlkeel-opencode`
- npm publication for the Pi extension package `@aryaminus/controlkeel-pi-extension`
- `.vsix` packaging for the VS Code companion
- conditional VS Code marketplace publication when `VSCE_PAT` is configured

Hosts without a documented published package flow remain attach-first in the docs and `/skills`.

For `skills.sh`, there is no separate marketplace submission step documented today. The official FAQ says leaderboard/listing visibility happens automatically from anonymous `npx skills add <owner/repo>` installs.

## Post-attach verification and common MCP startup failures

After any `controlkeel attach <host>`, run:

```bash
controlkeel attach doctor
```

Then follow host-specific checks:

- Claude Code: `claude mcp get controlkeel`
- OpenCode: `opencode mcp list`
- Codex CLI: restart Codex and confirm the configured MCP server from `.codex/config.toml` is loaded
- Cursor/Windsurf/Continue/Cline: restart the host and confirm the ControlKeel MCP entry is present in host settings/config

Common failure causes and fixes:

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| MCP server is registered but shows failed/disconnected | Host cannot launch `controlkeel` from its PATH | Set `CONTROLKEEL_BIN` to an absolute `controlkeel` path and re-run `controlkeel attach <host>` |
| MCP appears attached but tools fail immediately on first call | Host startup race after launch | Wait a few seconds, retry once, then run `controlkeel attach doctor` |
| Attach succeeds but host ignores repo-level config | Host trust/workspace policy is blocking project config | Trust the repo/workspace and restart host |
| Conflicting old and new host config files | Host reads a legacy config path | Re-run `controlkeel attach <host>` so CK rewrites canonical + compatibility config files |

Security note: redact bearer tokens, proxy URLs with embedded credentials, and service-account secrets before sharing logs/transcripts.

## Update behavior after a new CK release

ControlKeel does not silently rewrite repo files or host plugin directories when a new release ships.

- `controlkeel update` checks the latest GitHub release, reports the current install channel, and prints the safest next upgrade command.
- `controlkeel update --apply` can perform the upgrade directly when the install channel is safely automatable from CK.
- `controlkeel update --sync-attached` refreshes attached repo-local or user-scope bundles, which covers MCP wrappers, native skills, hooks, commands, agents, and plugin-style install surfaces that CK manages through `attach`.

- Upgrading the main `controlkeel` binary through Homebrew, npm bootstrap, or the release installers updates the CLI itself.
- MCP registrations that call `controlkeel` directly, or call the generated `controlkeel-mcp` wrapper, start using the new binary automatically on the next host invocation.
- CK now auto-syncs stale attached bundles on the next governed CLI load when the attachment has a real install target and scope. In practice, repo-local and user-scope `controlkeel attach <host>` installs can self-heal to the current CK version.
- Some artifacts still do not auto-refresh. That includes exported tarballs, local `--plugin-dir` installs, manually copied plugin directories, and sideloaded `.vsix` files.
- Refresh those by rerunning `controlkeel attach <host>` or the relevant `controlkeel skills install` / `controlkeel plugin export` flow.
- Published host packages follow the host package manager:
  - OpenCode / Pi npm packages update through npm or the host’s extension updater.
  - VS Code marketplace installs can auto-update through VS Code itself; sideloaded `.vsix` installs still require a newer package to be installed.
  - Local `--plugin-dir` installs do not auto-update; rebuild or reinstall the bundle.

For public, network-visible drift checks across docs URLs, npm packages, and installer endpoints, run `mix ck.host_audit`.

## Remote and browser behavior

CK also pulls a few practical host patterns from Plannotator for direct-install flows:

- `CONTROLKEEL_REMOTE=1`: treat the current environment as remote or forwarded; CK will avoid trying to auto-open a browser and will return the review URL instead.
- `CONTROLKEEL_BROWSER=/path/to/browser` or `BROWSER=...`: force a specific browser command for `controlkeel review plan open`.
- `CONTROLKEEL_REVIEW_EMBED=vscode_webview`: prefer the VS Code companion embed path instead of an external browser.
- `CONTROLKEEL_AUTO_OPEN_REVIEWS=0`: disable automatic browser launching entirely. Test runs already default to this behavior.

## External browser companions

ControlKeel does not currently ship its own browser engine. When a governed workflow needs lightweight headless browsing or scraping, the cleanest fit is usually an external MCP- or CDP-capable browser runtime alongside CK rather than pretending browser automation is a native CK attach family.

One notable option is [Lightpanda](https://lightpanda.io/), a third-party headless browser built for automation and AI-agent workloads. Its open-source binary now exposes a native stdio MCP server (`lightpanda mcp`) and also supports CDP-compatible tooling, which makes it a practical companion when:

- an agent needs fast, low-memory page navigation and extraction
- Chrome or Chromium are too heavy for the target runtime
- you want browser access through a dedicated MCP server instead of mixing that logic into CK itself

Lightpanda is best treated as optional infrastructure next to ControlKeel, not as a ControlKeel-managed host target:

- CK remains the governance, review, proof, and policy layer
- Lightpanda can supply browser navigation and extraction through its own MCP server or CDP surface
- the operator should still apply normal trust-boundary, robots.txt, and rate-limit discipline for any automated browsing or scraping workflow

If you wire it into a repo-local MCP config, keep the support claim explicit: this is a third-party browser companion that CK can coexist with, not a native `controlkeel attach lightpanda` path.
