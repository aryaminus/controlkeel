# @aryaminus/controlkeel

This package is a bootstrap installer for the native ControlKeel CLI.

The npm and GitHub Packages channels use the same bootstrap package when published. The native binary is downloaded from the matching versioned GitHub Release on first use, not during installation.

## Install

```bash
npm i -g @aryaminus/controlkeel
# or: pnpm add -g @aryaminus/controlkeel
# or: yarn global add @aryaminus/controlkeel

# one-off run
npx @aryaminus/controlkeel@latest
```

The package installs the `controlkeel` command. The native binary is automatically downloaded on first use.

Companion package names used by supported host install paths:

- [`@aryaminus/controlkeel-opencode`](https://www.npmjs.com/package/@aryaminus/controlkeel-opencode) for OpenCode plugin installs
- [`@aryaminus/controlkeel-pi-extension`](https://www.npmjs.com/package/@aryaminus/controlkeel-pi-extension) for Pi extension installs

Main project docs:

- [Repository README](https://github.com/aryaminus/controlkeel#readme)
- [Getting started](https://github.com/aryaminus/controlkeel/blob/main/docs/getting-started.md)
- [Agent integrations](https://github.com/aryaminus/controlkeel/blob/main/docs/agent-integrations.md)
- [Support matrix](https://github.com/aryaminus/controlkeel/blob/main/docs/support-matrix.md)

After the first run, complete the repo-local path with `controlkeel setup`, `controlkeel attach <host>`, `controlkeel attach doctor`, `controlkeel provider doctor`, `controlkeel status`, and `controlkeel findings`.

You can also install the same bootstrap package from GitHub Packages:

```bash
echo "@aryaminus:registry=https://npm.pkg.github.com" >> ~/.npmrc
echo "//npm.pkg.github.com/:_authToken=YOUR_GITHUB_TOKEN_WITH_READ_PACKAGES" >> ~/.npmrc
npm i -g @aryaminus/controlkeel --registry=https://npm.pkg.github.com
```

## Security

This package uses a lazy download model for maximum security:

- No install scripts (removed postinstall)
- Fixed release repository and package version; environment flags cannot redirect the download source
- Plain GitHub Release URLs for transparent scanner and reviewer visibility
- SHA-256 checksum verification for all downloads

The native binary is downloaded on first use rather than during installation. For detailed information about security practices, see [SECURITY.md](SECURITY.md).

For manual installation, download the matching binary and checksum from [GitHub Releases](https://github.com/aryaminus/controlkeel/releases/latest). Release bundles or manifests may support local plugin installation, but they do not imply publication in a host's public marketplace.

<!-- mcp-name: io.github.aryaminus/controlkeel -->
