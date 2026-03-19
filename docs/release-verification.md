# Release Verification

This checklist is the manual gate before enabling automatic version bumping.

## First known-good SHA

- Release Smoke green on `main`: 0d568a5cb14b6b409d78cd2095bfbba5b079cb68
- Tag-triggered Release green: 494b536c20a13403f9e84970509074af5e4b4b92
- GitHub release assets published correctly: 494b536c20a13403f9e84970509074af5e4b4b92

Update this file with the first confirmed good SHA before enabling `CONTROLKEEL_RELEASE_AUTOTAG_ENABLED`.

## Checklist

1. Confirm the latest [Release Smoke](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml) run on `main` is green for Linux, macOS Intel, macOS Apple Silicon, and Windows smoke.
2. Confirm the latest tag-triggered [Release](https://github.com/aryaminus/controlkeel/actions/workflows/release.yml) run is green and uploaded all Burrito artifacts.
3. Verify release notes/changelog content matches the tagged version.
4. Set repository variable `CONTROLKEEL_RELEASE_AUTOTAG_ENABLED=true`.
5. Ensure `PAT_TOKEN` is configured so the bump workflow can push commits and tags that trigger downstream workflows.
6. If Homebrew publication is enabled, ensure `HOMEBREW_TAP_TOKEN` can push to `aryaminus/homebrew-controlkeel`.
7. If npm publication is enabled, ensure `NPM_TOKEN` is configured for `@aryaminus/controlkeel`.
