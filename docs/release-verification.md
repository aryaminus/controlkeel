# Release Verification

This checklist is the manual gate before enabling automatic version bumping.

## Latest known-good checkpoints

- Release Smoke green on `main`: `5e73158d57a1c8743417cc02f251fcd1a9f4ed96` ([workflow run](https://github.com/aryaminus/controlkeel/actions/runs/23518768141), 2026-03-25)
- Tag-triggered Release green: `10e3327bfe4e676bbb2271f5b9d359398be5f0a9` (`v0.1.8`, [workflow run](https://github.com/aryaminus/controlkeel/actions/runs/23518952206))
- GitHub release assets published correctly: `10e3327bfe4e676bbb2271f5b9d359398be5f0a9` (`v0.1.8`, [GitHub Release](https://github.com/aryaminus/controlkeel/releases/tag/v0.1.8))

Re-verify after each release: confirm the latest successful [Release Smoke](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml) on `main` and the latest tag-triggered [Release](https://github.com/aryaminus/controlkeel/actions/workflows/release.yml), then refresh the checkpoints above.

Keep this file on the latest confirmed green SHAs before relying on `CONTROLKEEL_RELEASE_AUTOTAG_ENABLED`.

`Release Smoke` is the canonical release-candidate build for a SHA. Tag-triggered `Release` should publish the matching smoke artifact set for that same SHA instead of rebuilding binaries again.

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
