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

## 2. Initialize a target project

Change into the project you want to govern and run:

```bash
controlkeel init
```

Source wrapper:

```bash
mix ck.init
```

This writes:

- `controlkeel/project.json`
- `controlkeel/bin/controlkeel-mcp`
- `/controlkeel` in `.gitignore`

## 3. Attach Claude Code

```bash
controlkeel attach claude-code
```

Source wrapper:

```bash
mix ck.attach claude-code
```

ControlKeel registers a local MCP server using the generated project-local wrapper so Claude Code can call back into the governed runtime.

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
- `/ship` for install-to-first-finding metrics

## Notes

- The generated MCP wrapper expects `controlkeel` on your `PATH` by default.
- You can override the binary path with `CONTROLKEEL_BIN=/absolute/path/to/controlkeel`.
- Packaged local mode creates its own database and secret key automatically when the usual env vars are not set.
