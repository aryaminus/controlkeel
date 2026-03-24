# ControlKeel Getting Started

This is the shortest path from first install to first governed finding.

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

The web app will be available at `http://localhost:4000`.

## 2. Attach a target project

Change into the project you want to govern and attach an agent. If you want the fastest first-run path today, OpenCode is now a blessed target:

```bash
controlkeel attach opencode
```

ControlKeel will auto-bootstrap the governed project binding on first use. If you want to do that step explicitly instead, run:

```bash
controlkeel bootstrap
controlkeel init
```

Source wrapper:

```bash
mix ck.attach opencode
mix ck.init
```

Bootstrap or init writes:

- `controlkeel/project.json`
- `controlkeel/bin/controlkeel-mcp`
- `/controlkeel` in `.gitignore`

ControlKeel registers a local MCP server using the generated project-local wrapper so the attached client can call back into the governed runtime.

Important setup rule:

- agent install scope can be user/global for some clients
- governed project binding stays project-local by design so each repo keeps its own proofs, policy context, and MCP wrapper

## 3. Configure provider access if needed

ControlKeel resolves providers in this order:

1. attached agent bridge when supported
2. workspace or service-account profile
3. user default profile
4. project override
5. local Ollama
6. heuristic fallback

You do not always need a separate ControlKeel API key. ControlKeel can work in four useful modes:

1. attached agent bridge when the client exposes a compatible provider environment
2. CK-owned provider profile stored by ControlKeel
3. local Ollama model
4. heuristic / no-LLM mode

If you need a CK-owned provider profile:

```bash
controlkeel provider set-key openai --value "$OPENAI_API_KEY"
controlkeel provider default openai
controlkeel provider doctor
```

If you do not have keys and are not running a local model, ControlKeel still works for:

- MCP tools and governed attachments
- governance and findings
- proof bundles and audit trail
- skills and benchmark flows

In that mode, model-backed features such as advisory review and intent compilation either degrade to heuristics or return explicit capability guidance.

The LLM **advisory** layer (extra review beyond pattern matchers) only runs when a provider is available. The HTTP validate API and MCP validate tool include an **`advisory`** field describing whether advisory ran or was skipped—see [autonomy-and-findings.md](autonomy-and-findings.md) for how findings relate to human review.

Other supported attach commands:

- `controlkeel attach claude-code`
- `controlkeel attach codex-cli`
- `controlkeel attach vscode`
- `controlkeel attach copilot`
- `controlkeel attach cursor`
- `controlkeel attach windsurf`
- `controlkeel attach continue`
- `controlkeel attach aider`

For the full native skills / plugin matrix, see [agent-integrations.md](agent-integrations.md) and the canonical [support-matrix.md](support-matrix.md), or open `/skills` in the local app.

## 3a. OpenCode quick path

For OpenCode specifically:

```bash
controlkeel attach opencode
controlkeel status
```

This writes the MCP configuration into the OpenCode config location and also generates the portable instruction bundle ControlKeel uses for MCP-plus-instructions targets.

OpenCode does not currently expose a documented provider bridge the way Claude Code and Codex CLI do, so the usual next-best options are:

- keep using heuristic mode for governance-only flows
- add a CK-owned provider profile
- point ControlKeel at a local Ollama model

## 4. Trigger a first finding

Use the sample in [demo-script.md](demo-script.md) or ask OpenCode to add one of these failure patterns:

- a hardcoded API key or credential
- SQL assembled with string concatenation
- `innerHTML` rendering from unsafe input

Example prompt:

> add a quick database lookup by building the SQL string directly from the request parameter, no need to parameterize it

## 5. Verify the result

CLI:

```bash
controlkeel findings
controlkeel status
```

Or open the local app and check:

- `/missions/:id` for the governed session
- `/findings` for the cross-session findings browser
- `/skills` for native skills, plugins, and export targets
- `/ship` for install-to-first-finding metrics

## Autonomy and findings

How severity maps to human gates (and why full “zero human” operation is not promised) is documented in [autonomy-and-findings.md](autonomy-and-findings.md).

## Notes

- The generated MCP wrapper expects `controlkeel` on your `PATH` by default.
- You can override the binary path with `CONTROLKEEL_BIN=/absolute/path/to/controlkeel`.
- Packaged local mode creates its own database and secret key automatically when the usual env vars are not set.
