# ControlKeel Packages and Distribution

This is the package catalog. Host support truth lives in [support-matrix.md](support-matrix.md); first-run setup lives in [getting-started.md](getting-started.md).

## Package categories

### Bootstrap package

| Package | Purpose | Install |
| --- | --- | --- |
| `@aryaminus/controlkeel` | Cross-platform bootstrapper that downloads the matching release binary. | `npm i -g @aryaminus/controlkeel` |

Install this first before using companion packages or generated bundles.

### Companion packages

| Package | Host | Use |
| --- | --- | --- |
| `@aryaminus/controlkeel-opencode` | OpenCode | Direct plugin package path. Still run `controlkeel attach opencode` for repo-local MCP, commands, agents, and skills. |
| `@aryaminus/controlkeel-pi-extension` | Pi | Pi extension path. Still run `controlkeel attach pi` for repo-local governance files. |

### Distribution bundles

Release artifacts and `controlkeel runtime export <target>` generate bundles for:

- host-native integrations such as OpenCode, Claude Code, Codex CLI, Copilot, Cursor, Windsurf, and others listed in [support-matrix.md](support-matrix.md)
- headless/runtime targets such as Devin, Open SWE, Executor, virtual-bash, and Cloudflare Workers
- framework adapters and instructions-only bundles
- VS Code companion extension and release tarballs

A release bundle may contain a plugin or marketplace manifest so a host can install it locally. That does not mean the bundle has been published to, reviewed by, or listed in that host's public marketplace. Treat marketplace publication as a separate channel and verify the listing in the marketplace itself.

### Skills registry

ControlKeel skills can also be installed through skills.sh:

```bash
npx skills add https://github.com/aryaminus/controlkeel
npx skills add https://github.com/aryaminus/controlkeel --skill controlkeel-governance
```

## Installation patterns

Standard setup:

```bash
npm i -g @aryaminus/controlkeel
controlkeel setup
controlkeel attach <host>
controlkeel attach doctor
controlkeel provider doctor
controlkeel status
controlkeel findings
```

Run this sequence in the repository being governed. Attach defaults to project scope. `--scope user` is accepted only by targets that advertise it and mutates user-level host configuration, not project binding or project evidence.

Companion package path:

```bash
npm i -g @aryaminus/controlkeel
# install the host companion through that host's package mechanism
controlkeel attach <host>
```

Runtime export path:

```bash
npm i -g @aryaminus/controlkeel
controlkeel runtime export <runtime>
```

## Versioning and supply chain

- Keep bootstrap, companion packages, and generated bundles on the same ControlKeel version.
- GitHub Releases are the canonical source for binaries, checksums, plugin tarballs, exported native bundles, and the VS Code companion `.vsix`.
- Direct CLI updates pin downloads to `aryaminus/controlkeel` and require the release checksum before atomic replacement. The checksum detects corruption or mismatch within a release; it is not independent proof against a compromised release origin. Shell, PowerShell, and npm installers can additionally verify keyless cosign provenance when cosign is available.
- A successful CI run only authorizes a version bump while its exact commit remains current `main`. Native release-smoke evidence is created later by the commit-bound release-candidate workflow and is required by the tag release workflow before publication.
- The `releases/latest/download/...` installers are versioned release assets selected by GitHub's latest-release redirect. The `raw.githubusercontent.com/.../main/...` installers are mutable snapshots of the current default branch and can change before the next release.
- Release artifacts and marketplace publication are independent; an exported marketplace-ready bundle is not evidence of a public marketplace listing.
- Run `controlkeel update`, then rerun `controlkeel attach <host>` when repo-local artifacts need syncing.

## Troubleshooting

| Problem | Check |
| --- | --- |
| Package not found | Use scoped names such as `@aryaminus/controlkeel`, not `controlkeel`. |
| Attach command not working | Run `controlkeel attach doctor`, then check [support-matrix.md](support-matrix.md). |
| Companion package installed but CK unavailable | Run `controlkeel attach <host>` and restart the host. |
| Version mismatch | Update packages and rerun attach to sync generated files. |

## Quick reference

| I want to... | Command |
| --- | --- |
| Install ControlKeel | `npm i -g @aryaminus/controlkeel` |
| Attach to my host | `controlkeel attach <host>` |
| List attach targets | `controlkeel attach --list` |
| Export runtime bundle | `controlkeel runtime export <runtime>` |
| Check attachment health | `controlkeel attach doctor` |
| Update ControlKeel | `controlkeel update` |
| Get help | `controlkeel help` |
