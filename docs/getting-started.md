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

Change into the project you want to govern and attach an agent:

```bash
controlkeel attach claude-code
```

ControlKeel will auto-bootstrap the governed project binding on first use. If you want to do that step explicitly instead, run:

```bash
controlkeel bootstrap
controlkeel init
```

Source wrapper:

```bash
mix ck.attach claude-code
mix ck.init
```

Bootstrap or init writes:

- `controlkeel/project.json`
- `controlkeel/bin/controlkeel-mcp`
- `/controlkeel` in `.gitignore`

ControlKeel registers a local MCP server using the generated project-local wrapper so the attached client can call back into the governed runtime.

## 3. Configure provider access if needed

ControlKeel resolves providers in this order:

1. attached agent bridge when supported
2. workspace or service-account profile
3. user default profile
4. project override
5. local Ollama
6. heuristic fallback

If you need a CK-owned provider profile:

```bash
controlkeel provider set-key openai --value "$OPENAI_API_KEY"
controlkeel provider default openai
controlkeel provider doctor
```

If you do not have keys and are not running a local model, ControlKeel still works for MCP, governance, proofs, skills, and benchmarks. Model-backed features degrade cleanly to heuristics.

Other supported attach commands:

- `controlkeel attach codex-cli`
- `controlkeel attach vscode`
- `controlkeel attach copilot`
- `controlkeel attach cursor`
- `controlkeel attach windsurf`
- `controlkeel attach continue`
- `controlkeel attach aider`

For the full native skills / plugin matrix, see [agent-integrations.md](agent-integrations.md) or open `/skills` in the local app.

## 4. Trigger a first finding

Use the sample in [demo-script.md](demo-script.md) or ask Claude Code to add one of these failure patterns:

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

## Notes

- The generated MCP wrapper expects `controlkeel` on your `PATH` by default.
- You can override the binary path with `CONTROLKEEL_BIN=/absolute/path/to/controlkeel`.
- Packaged local mode creates its own database and secret key automatically when the usual env vars are not set.
