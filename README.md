# ControlKeel

ControlKeel is the control plane that turns AI coding into production engineering. It sits above Claude Code, Codex, Cursor, Bolt, Replit, and other agent tools to enforce validation, budgets, findings review, and governed execution.

## Packaged Binary

1. Start the local app:
   `controlkeel`
2. In the project you want to govern:
   `controlkeel init`
3. Attach Claude Code:
   `controlkeel attach claude-code`
4. Trigger a known-bad change:
   ask Claude Code to add a hardcoded credential or unsafe SQL query.
5. Verify the first finding:
   `controlkeel findings`
   or open the local web app and inspect the mission dashboard.

## Source Setup

1. Install dependencies and set up the database:
   `mix setup`
2. Start the app:
   `mix phx.server`
3. In the project you want to govern, run the Mix-backed commands from the same source install:
   `mix ck.init`
   `mix ck.attach claude-code`
   `mix ck.status`

## CLI Surface

Packaged binary:

```bash
controlkeel
controlkeel serve
controlkeel init [--industry ...] [--agent ...] [--idea ...] [--features ...] [--budget ...]
controlkeel attach claude-code
controlkeel status
controlkeel findings [--severity ...] [--status ...]
controlkeel approve <finding-id>
controlkeel mcp [--project-root /abs/path]
controlkeel help
controlkeel version
```

Source wrappers:

```bash
mix ck.init
mix ck.attach claude-code
mix ck.status
mix ck.findings
mix ck.approve 12
mix ck.mcp --project-root /abs/path
```

## Guides

- [Getting started](docs/getting-started.md)
- [Demo script](docs/demo-script.md)

## Packaging

ControlKeel now ships with Burrito-based single-binary packaging instead of Bakeware. Build native or targeted artifacts with:

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
BURRITO_TARGET=linux MIX_ENV=prod mix release
```

Built artifacts are written to `burrito_out/`.
