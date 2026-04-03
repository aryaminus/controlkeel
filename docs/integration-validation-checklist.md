# ControlKeel Integration Validation Checklist

This checklist tracks real-world validation of install channels and agent integrations.

For the full QA procedure and feature-by-feature test plan, use [qa-validation-guide.md](qa-validation-guide.md).

## Scope

- Install channels: Homebrew, npm global
- IDE/agent path: GitHub Copilot in VS Code (repo-native companion)
- Agent path: OpenCode (native companion + MCP)
- Catalog truth audit: alias/framework/unverified inventory

## Validation Summary (2026-04-01)

### Install channels

- [x] Homebrew channel validated on macOS
  - `brew tap aryaminus/controlkeel && brew install controlkeel`
  - `controlkeel version` returned `0.1.13`
- [x] npm channel validated on macOS
  - `npm i -g @aryaminus/controlkeel --force`
  - `controlkeel version` returned `0.1.15`
- [x] Conflict behavior validated
  - Homebrew and npm both write `/opt/homebrew/bin/controlkeel`
  - npm install without `--force` fails with `EEXIST`
  - Recovery validated by uninstalling npm package and relinking brew

### Copilot in VS Code (repo-native)

- [x] `controlkeel attach copilot` executed successfully
- [x] Generated artifacts validated:
  - `.github/skills/`
  - `.github/agents/controlkeel-operator.agent.md`
  - `.github/mcp.json`
  - `.vscode/mcp.json`
  - `.github/copilot-instructions.md`
- [x] MCP stdio runtime validated with framed `initialize` + `tools/list`
- [x] Tool inventory includes core and extended CK tools (`ck_context`, `ck_validate`, `ck_finding`, `ck_budget`, `ck_route`, `ck_delegate`, `ck_skill_list`, `ck_skill_load`, plus optimizer/deployment/outcome tools)

### OpenCode integration

- [x] Crash reproduced against installed binary (`0.1.13`) when existing OpenCode config JSON is malformed
- [x] Root cause identified and fixed in source:
  - `lib/controlkeel/cli.ex` (`write_ide_mcp_config/4`) now safely handles decode failures
- [x] Native attach behavior corrected in source:
  - `attach opencode` now installs `opencode-native` bundle during native attach flow
- [x] Regression test added and passing:
  - `test/controlkeel/cli_runtime_test.exs`
  - malformed OpenCode config recovery + native artifact generation assertions
- [x] Local codepath validation passed:
  - `mix ck.attach opencode`
  - `.opencode/plugins/controlkeel-governance.ts`
  - `.opencode/agents/controlkeel-operator.md`
  - `.opencode/commands/controlkeel-review.md`
  - `.opencode/mcp.json`

## Follow-up TODO

### Release and channel parity

- [ ] Cut a new ControlKeel release so Homebrew/npm binaries include the OpenCode malformed-config fix
- [ ] Publish release notes calling out:
  - OpenCode attach robustness fix
  - Native attach target mapping correction
- [ ] Validate post-release channels without `--force` path clobbering guidance ambiguity

### Documentation alignment

- [ ] Add a short install-channel note in docs explaining Homebrew/npm binary path collisions on same machine
- [ ] Add explicit Copilot-in-VSCode runtime check recipe (framed MCP `tools/list` probe)
- [ ] Add OpenCode verification recipe to getting-started docs

### Optional hardening

- [ ] Add a CLI self-check command to detect binary ownership conflict (`brew` vs `npm`) and print remediation guidance
- [ ] Add a small docs/code consistency test for support-matrix claims vs `AgentIntegration.catalog/0`

## Operator runbook

### Install channels

```bash
brew tap aryaminus/controlkeel && brew install controlkeel
npm i -g @aryaminus/controlkeel
controlkeel version
```

If npm fails with `EEXIST`, either:

```bash
npm i -g @aryaminus/controlkeel --force
```

or keep Homebrew as owner and skip npm global install.

### Copilot in VS Code

```bash
controlkeel attach copilot
```

Check generated files:

```bash
ls .github/skills .github/agents .github/mcp.json .vscode/mcp.json .github/copilot-instructions.md
```

Probe MCP tools over stdio (framed protocol):

```bash
node -e 'const init=JSON.stringify({jsonrpc:"2.0",id:1,method:"initialize",params:{protocolVersion:"2024-11-05",capabilities:{},clientInfo:{name:"ck-test",version:"1.0"}}}); const list=JSON.stringify({jsonrpc:"2.0",id:2,method:"tools/list",params:{}}); process.stdout.write(`Content-Length: ${Buffer.byteLength(init)}\r\n\r\n${init}`); process.stdout.write(`Content-Length: ${Buffer.byteLength(list)}\r\n\r\n${list}`);' | ./controlkeel/bin/controlkeel-mcp
```

### OpenCode

```bash
controlkeel attach opencode
```

Or from source while validating unreleased fixes:

```bash
mix ck.attach opencode
```

Check generated files:

```bash
ls .opencode/plugins .opencode/agents .opencode/commands .opencode/mcp.json
```
