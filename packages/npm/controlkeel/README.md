# @aryaminus/controlkeel

This package is a bootstrap installer for the native ControlKeel CLI.

Both npmjs and GitHub Packages publish the same bootstrap package. In both cases, installation downloads the matching native ControlKeel binary from GitHub Releases.

## Install

```bash
npm i -g @aryaminus/controlkeel
# or: pnpm add -g @aryaminus/controlkeel
# or: yarn global add @aryaminus/controlkeel

# one-off run
npx @aryaminus/controlkeel@latest
```

The package installs and exposes the `controlkeel` command.

You can also install the same bootstrap package from GitHub Packages:

```bash
echo "@aryaminus:registry=https://npm.pkg.github.com" >> ~/.npmrc
echo "//npm.pkg.github.com/:_authToken=YOUR_GITHUB_TOKEN_WITH_READ_PACKAGES" >> ~/.npmrc
npm i -g @aryaminus/controlkeel --registry=https://npm.pkg.github.com
```
