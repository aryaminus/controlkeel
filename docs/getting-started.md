# ControlKeel Getting Started

This guide is the shortest path from install to a governed finding. It intentionally avoids duplicating the host catalog, package catalog, or benchmark reference.

## 1. Start ControlKeel

Packaged binary:

```bash
controlkeel
```

Source checkout:

```bash
mix setup
mix phx.server
```

The web app runs at `http://localhost:4000`.

## 2. Attach one project and one host

In the repository you want to govern:

```bash
controlkeel setup
controlkeel attach opencode
```

OpenCode is the fastest current first-run attach path. The fastest value proof is host-independent: run the with-vs-without CK benchmark below, then attach any supported host from the canonical [support matrix](support-matrix.md) and mechanism guide in [agent integrations](agent-integrations.md).

Useful verification loop:

```bash
controlkeel attach doctor
controlkeel provider doctor
controlkeel status
controlkeel findings
```

If the host requires workspace trust or a restart after attach, do that before validating MCP/tool availability. Project binding stays repo-local so each repo keeps its own proofs, policy context, and MCP wrapper.

Attach uses project scope by default and mutates only the governed repository. Use `--scope user` only when the selected host advertises user scope; that installs host-level files under your user configuration, while project binding, policy context, and evidence remain project-specific.

Local stdio MCP exposes the complete local tool catalog for that project. Hosted MCP is a separate service-account OAuth path with a deliberately narrower, scope-authorized tool set; local-only filesystem or sandbox capabilities must not be inferred from hosted access. See [support-matrix.md](support-matrix.md#local-stdio-mcp) for the exact sets.

## 3. Provider access, only if needed

CK governance, findings, proof bundles, skills, and deterministic validation work without a model key. Model-backed advisory review and intent compilation need one of:

1. attached agent bridge when supported
2. CK-owned provider profile
3. local Ollama/OpenAI-compatible backend
4. heuristic fallback for non-model flows

Typical CK-owned profile:

```bash
controlkeel provider set-key openai --value "$OPENAI_API_KEY"
controlkeel provider default openai
controlkeel provider doctor
```

OpenAI-compatible local or hosted backend:

```bash
controlkeel provider set-base-url openai --value http://127.0.0.1:1234
controlkeel provider set-model openai --value local-model
controlkeel provider default openai
```

Treat custom gateways as trust boundaries. Benchmark the concrete setup before making quality or cost claims.

## 4. Trigger the first finding

Use a real pending change, or run a controlled validation benchmark:

```bash
controlkeel benchmark run \
  --suite host_comparison_v1 \
  --subjects null_policy_baseline,controlkeel_validate \
  --baseline-subject null_policy_baseline
controlkeel benchmark compare <run-id>
```

This produces a reproducible with-vs-without score: no CK policy gate vs deterministic CK validation. Pair it with `benign_baseline_v1` before making user-facing claims.

For live work, ask the attached agent to make the actual change and let CK validate the diff before it lands.

## 5. Verify the result

CLI:

```bash
controlkeel findings
controlkeel status
```

Web:

- `/missions/:id` — governed session
- `/findings` — findings browser
- `/proofs` — proof bundles
- `/deploy` — deployment guidance and generated config previews
- `/benchmarks` — benchmark evidence

## Notes

- The generated MCP wrapper expects `controlkeel` on your `PATH` by default.
- Override the binary path with `CONTROLKEEL_BIN=/absolute/path/to/controlkeel` when needed.
- Packaged local mode creates its own database and secret key automatically when the usual env vars are unset.
- Local mode remains the default trust anchor; cloud/headless paths add shared governance only when configured.

## Next docs

- Host support and protocol truth: [support-matrix.md](support-matrix.md)
- Integration mechanisms and fallback support: [agent-integrations.md](agent-integrations.md)
- Cost and provider limits: [cost-governance.md](cost-governance.md)
- Autonomy and review gates: [autonomy-and-findings.md](autonomy-and-findings.md)
- Large-codebase patterns: [large-codebase-patterns.md](large-codebase-patterns.md)
