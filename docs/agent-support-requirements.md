# Agent Support Requirements

## Acceptance criteria for a shipped integration

An integration is only considered shipped when all of the following are true:

1. It has a canonical row in `ControlKeel.AgentIntegration.catalog/0`.
2. Its support class is accurate.
3. Its auth ownership is accurate.
4. Its MCP mode and skills mode are accurate.
5. It has a real CLI path:
   - `controlkeel attach <id>` for `attach_client`
   - `controlkeel runtime export <id>` for `headless_runtime`
6. It has at least one tested bundle or export target when applicable.
7. It is documented in:
   - [support-matrix.md](support-matrix.md)
   - [agent-integrations.md](agent-integrations.md)
8. It does not rely on undocumented upstream behavior.

## Requirements by support class

### `attach_client`

- Must have a documented config, extension, plugin, rules, hints, or repo-native surface.
- Must expose a truthful `preferred_target`.
- Must provide CK tool access through MCP, native skills, plugin bundle, or equivalent companion files.
- Must have CLI attach coverage and tests.

### `headless_runtime`

- Must not pretend to be a local attach command.
- Must export the files a hosted or asynchronous runtime needs:
  - `AGENTS.md`
  - runtime README or recipe
  - MCP or webhook guidance as needed

### `framework_adapter`

- Must not be surfaced as `controlkeel attach`.
- Must be routed through benchmark, policy-training, or runtime-harness exports.

### `provider_only`

- Must not be surfaced as `controlkeel attach`.
- Must be reachable through CK provider/profile flows.
- OpenAI-compatible backends must document `base_url` and `model` usage.

### `alias`

- Must resolve to a canonical shipped target.
- Must not drift from the canonical target’s auth or companion story.

### `unverified`

- Must remain visible as research inventory only.
- Must not be described as shipped support.

## Current scope decisions

- Roo Code is shipped as a project-local attach target with `.roo/` and `.roomodes` support.
- Goose is shipped as an attach target with:
  - user-level Goose extension registration in `~/.config/goose/config.yaml`
  - project-level `.goosehints`, workflow recipe, `AGENTS.md`, and MCP companion files
- `rlm-agent`, `slate`, `retune`, `claw-code`, `claude-code-source-mirror`, `z-ai-cli`, `capydotai`, and `neosigma` remain intentionally unverified.

## Degraded-mode requirement

When no compatible provider is available, CK must still provide useful governance behavior:

- findings
- proofs
- budgets
- routing metadata
- benchmarks
- skills and MCP surfaces

Only true LLM-backed features may degrade to heuristic behavior or explicit capability guidance.
