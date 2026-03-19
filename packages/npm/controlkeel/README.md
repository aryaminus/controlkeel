# @aryaminus/controlkeel

This package is a bootstrap installer for the native ControlKeel CLI.

## Install

```bash
npm i -g @aryaminus/controlkeel
```

The package downloads the matching ControlKeel binary from GitHub Releases and exposes the `controlkeel` command.

You can also install the same bootstrap package from GitHub Packages:

```bash
echo "@aryaminus:registry=https://npm.pkg.github.com" >> ~/.npmrc
echo "//npm.pkg.github.com/:_authToken=YOUR_GITHUB_CLASSIC_PAT" >> ~/.npmrc
npm i -g @aryaminus/controlkeel --registry=https://npm.pkg.github.com
```
