# ControlKeel Status Audit

Date: March 19, 2026

This file replaces the earlier stale MVP audit. The previous version listed several gaps that are now already implemented in the repo. Treat this document as an internal maintainer status note, not a product roadmap pitch.

## Current Summary

- The original MVP checklist is materially complete.
- The repo is already beyond MVP: proof bundles, typed memory, benchmark engine, policy training artifacts, expanded domain packs, and native skills/plugin distribution are present.
- The true remaining roadmap work is the later Team/Platform branch and the infrastructure branch.
- Burrito packaging is implemented. Release Smoke and tag-triggered Release were verified green as of 2026-03-25 (see [docs/release-verification.md](../../docs/release-verification.md) for SHAs: smoke on `main` `5e73158…`, release `v0.1.8` `10e3327…`).

## MVP Gaps That Are Closed

1. Policy Studio is implemented.
   Evidence: `/policies` is routed in `lib/controlkeel_web/router.ex`, the screen exists in `lib/controlkeel_web/live/policy_studio_live.ex`, and LiveView coverage exists in `test/controlkeel_web/live/policy_studio_live_test.exs`.

2. Proof bundles and task completion gating are implemented.
   Evidence: persisted proof bundles exist in `lib/controlkeel/mission.ex` and `lib/controlkeel/mission/proof_bundle.ex`; proof browser routes exist at `/proofs` and `/proofs/:id`; proof payloads include `test_outcomes`, `diff_summary`, `risk_score`, `deploy_ready`, `rollback_instructions`, and `compliance_attestations`; mission tests cover completion gating and proof persistence.

3. Onboarding includes the budget input.
   Evidence: Step 1 in `lib/controlkeel_web/live/onboarding_live.ex` includes the daily budget field and plain-language guidance; onboarding tests exist in `test/controlkeel_web/live/onboarding_live_test.exs`.

4. Mission Control finding actions are wired.
   Evidence: `lib/controlkeel_web/live/mission_control_live.ex` includes approve, reject, and "View fix" actions with event handlers; coverage exists in `test/controlkeel_web/live/mission_control_live_test.exs`.

5. REST API tests exist.
   Evidence: controller coverage is present in `test/controlkeel_web/controllers/api_controller_test.exs`.

6. Mission Control already surfaces task dependencies, ready tasks, the ordered task checklist, the compliance donut, and launch confirmation state.
   Evidence: `Mission.session_task_graph/1` supplies dependency edges and ready-task ordering; `lib/controlkeel_web/live/mission_control_live.ex` renders the checklist with status badges, validation gates, rollback boundaries, confidence scores, the compliance score donut, and the "You're set" session confirmation banner.

## Additional Stale Claims Removed

- Agent Router is not missing. `lib/controlkeel/agent_router.ex` exists and learned policy artifacts can influence routing with heuristic fallback.
- Typed memory is not missing. Memory, proof, and resume systems are implemented in the mission and memory contexts.
- Benchmark engine is not missing. Suites, runs, results, UI, API, and CLI are implemented.
- Domain expansion is not missing for the current supported set. The expanded packs are already first-class.
- Native skills, MCP integrations, and plugin/export paths are not missing. The repo already ships skills, native target exports, and attach flows.
- CLI parity is not missing for `watch`. `controlkeel watch` is parsed and implemented in the runtime CLI.
- `controlkeel init` does not always require a separate manual attach step. The runtime CLI attempts Claude auto-attach when available and supports `--no-attach`.
- Task `confidence_score` and `rollback_boundary` already exist in the task schema, planner output, and Mission Control UI.
- LLM advisory is not an unimplemented placeholder. `lib/controlkeel/scanner/advisory.ex` exists as the advisory layer.

## Already Built Beyond MVP

- Proof + memory: immutable proof bundles, typed memory records, task checkpoints, pause/resume, proof browser, and MCP context enrichment.
- Benchmark engine: persisted benchmark suites, runs, multi-subject matrix execution, API, CLI, and dashboard.
- Policy training artifacts: offline training pipeline, promoted router and budget-hint artifacts, and runtime heuristic fallback.
- Domain expansion: the current pack registry and the expanded supported domain set are wired through onboarding, planning, scanning, and benchmark metadata.
- Native skills and agent integration: built-in skills, validation/export/install flows, MCP-backed loading, and native bundles for Claude, Codex, Copilot/VS Code, and related targets.

## What Is Actually Remaining Now

These are the real unfinished roadmap branches after the current repo state, not missing MVP work.

### Team / Platform Branch

- Shared workspaces with team policies and approvals.
- Org-level spend controls and budgets.
- Audit log PDF export for compliance reporting.
- Enterprise/team policy sets and broader team-scoped proxy/governance surfaces.
- CI/CD-oriented webhooks and integration surfaces beyond the current single-endpoint webhook notifier.

### Infrastructure Branch

- NATS JetStream for multi-node cloud deployments.
- Tauri desktop app for OS-level hooks and non-MCP agent coverage.

### Launch / Ops Checklist

- **CI:** Keep [Release Smoke](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml) on `main` and [Release](https://github.com/aryaminus/controlkeel/actions/workflows/release.yml) on tags green; refresh [docs/release-verification.md](../../docs/release-verification.md) when SHAs change.
- **Local smoke (optional):** With a packaged binary from GitHub Releases, run `controlkeel`, `controlkeel attach opencode`, `controlkeel findings`, `controlkeel status` and align docs if behavior drifts.
- **Ship:** Tag releases and changelog/release notes per your release process when ready for the next version.

## Default Interpretation Going Forward

- Do not reopen the old MVP gap list unless a concrete regression appears in the codebase or tests.
- Treat the next product work as Team/Platform and infrastructure work, not as missing proof, policy, onboarding, Mission Control, router, memory, benchmark, or skills functionality.
- Treat release packaging as implemented product work with active verification, not as a missing subsystem.
