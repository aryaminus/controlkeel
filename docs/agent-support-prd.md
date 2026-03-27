# Agent Support PRD

## Goal

ControlKeel should expose a truthful, typed agent support model instead of a flat list of names. Every shipped integration must clearly answer:

- how CK attaches to the agent or runtime
- how the agent or runtime calls CK
- who owns model auth
- what still works without provider access

## Product outcomes

1. A user can pick a supported agent and reach a governed workflow with one documented command.
2. A maintainer can tell whether a name is a real attach target, a headless runtime export, a framework adapter, a provider template, an alias, or still unverified.
3. CK does not over-promise support for upstream projects that do not expose a stable integration surface.

## Support classes

- `attach_client`
  - Real `controlkeel attach <id>` path.
  - Must include a documented config or install surface and companion bundle.
- `headless_runtime`
  - Real `controlkeel runtime export <id>` path.
  - Used for hosted or asynchronous runtimes such as Devin and Open SWE.
- `framework_adapter`
  - Benchmarks, policy training, or runtime harness adapter surface.
  - Not exposed as a fake local attach command.
- `provider_only`
  - CK-owned provider/model template only.
  - Used for OpenAI-compatible backends and local runtimes.
- `alias`
  - Maps a market name to a canonical shipped integration.
- `unverified`
  - Kept visible only as research inventory.

## Shipped non-Team scope

### Attachable clients

- Claude Code
- Codex CLI
- Cline
- Roo Code
- Goose
- Hermes Agent
- OpenClaw
- Factory Droid
- Forge
- VS Code
- GitHub Copilot
- Cursor
- Windsurf
- Kiro
- Amp
- OpenCode
- Gemini CLI
- Continue
- Aider

### Headless runtimes

- Devin
- Open SWE

### Framework adapters

- DSPy
- GEPA
- DeepAgents
- FastMCP

### Provider-only entries

- Codestral
- Ollama
- vLLM
- SGLang
- LM Studio
- Hugging Face Inference Providers

## Auth ownership policy

- Use agent-owned auth only when the upstream exposes a documented bridge.
- Do not scrape or copy opaque third-party secrets out of local apps.
- If no agent bridge exists, CK falls back to:
  1. workspace or service-account profile
  2. user default profile
  3. project override
  4. local Ollama
  5. heuristic mode

## Native companion policy

- Native attach targets should install the strongest repo- or user-scoped companion the upstream truthfully supports.
- MCP-plus-instructions clients are allowed when no stronger native artifact exists.
- Project-local governance remains the default for proof, findings, and runtime binding even when a client also supports user-scope install.

## Release policy

- Release bundles should be generated for release-qualified targets in `SkillTarget.release_targets/0`.
- Published bundles must match the typed support inventory in the docs and code.
