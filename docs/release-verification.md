# Release Verification

This checklist is the manual gate before enabling automatic version bumping.

## First known-good SHA

- Release Smoke green on `main`: a134760386bd745dd79a4d678031b7199f6d934f
- Tag-triggered Release green: 2ea6be1c39265a57997822ad7f37d2338f4573a0 (`v0.1.6`)
- GitHub release assets published correctly: 2ea6be1c39265a57997822ad7f37d2338f4573a0 (`v0.1.6`)

Update this file with the first confirmed good SHA before enabling `CONTROLKEEL_RELEASE_AUTOTAG_ENABLED`.

## Checklist

1. Confirm the latest [Release Smoke](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml) run on `main` is green for Linux, macOS Intel, macOS Apple Silicon, and Windows smoke.
2. Confirm the latest tag-triggered [Release](https://github.com/aryaminus/controlkeel/actions/workflows/release.yml) run is green and uploaded all Burrito artifacts.
3. Verify the packaged install path matches current docs:
   - `controlkeel`
   - `controlkeel attach opencode`
   - `controlkeel findings`
   - `controlkeel status`
4. Verify the OpenCode quick-start and provider/no-key guidance in `README.md` and `docs/getting-started.md` still match runtime behavior.
5. Verify release notes/changelog content matches the tagged version.
6. Set repository variable `CONTROLKEEL_RELEASE_AUTOTAG_ENABLED=true`.
7. Ensure `PAT_TOKEN` is configured so the bump workflow can push commits and tags that trigger downstream workflows.
8. If Homebrew publication is enabled, ensure `HOMEBREW_TAP_TOKEN` can push to `aryaminus/homebrew-controlkeel`.
9. If npm publication is enabled, ensure `NPM_TOKEN` is configured for `@aryaminus/controlkeel`.
