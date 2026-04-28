# ControlKeel QA Validation Guide

This document is the end-to-end QA playbook for ControlKeel.

It is written for a software engineer who does **not** need Elixir experience. Treat ControlKeel as a black-box product with a CLI, a local web app, MCP surfaces, generated host companions, and release bundles.

The goal is to validate what ControlKeel claims to do, identify gaps or regressions, and report those issues clearly so Codex can fix them.

Use this guide together with:

- [support-matrix.md](support-matrix.md) for the code-aligned inventory
- [direct-host-installs.md](direct-host-installs.md) for package/plugin/extension install truth
- [agent-integrations.md](agent-integrations.md) for the integration model
- [autonomy-and-findings.md](autonomy-and-findings.md) for human-gate expectations
- [integration-validation-checklist.md](integration-validation-checklist.md) for current validation status

## 1. What ControlKeel Is

ControlKeel governs agent-generated software delivery.

At a high level, it can:

- start a local web app for mission control and review
- bootstrap a governed project
- attach supported coding hosts through MCP plus host-native files
- expose governance tools over local stdio MCP and hosted MCP
- expose a minimal A2A surface
- review plans, diffs, PR patches, and Socket reports
- record findings, proofs, audit logs, and release-readiness state
- export and install skills, plugins, extensions, and runtime bundles
- run or hand off governed work through supported agents
- manage providers, proxies, costs, deployment guidance, benchmarks, policy artifacts, and service accounts

Your job is to verify that those claims are true in practice.

## 2. QA Principles

Use these principles for every test:

- Test through published product surfaces first: CLI, generated files, HTTP endpoints, browser UI, packaged bundles.
- Prefer black-box validation over reading implementation details.
- Validate both a happy path and a failure path when possible.
- Capture exact commands, exact outputs, screenshots, and generated files.
- If a feature depends on an external host you do not have installed, still validate bundle export and generated artifacts.
- Distinguish between:
  - product bug
  - environment gap
  - unsupported host behavior
  - docs mismatch

## 3. Test Modes

Use three testing modes.

### A. Packaged product

Use this for end-user validation:

```bash
controlkeel version
controlkeel
```

### B. Source checkout

Use this when validating an unreleased fix:

```bash
mix setup
mix phx.server
mix ck.setup
mix ck.attach opencode
```

### C. Generated artifact validation

Use this when a host is unavailable locally:

```bash
controlkeel skills export --target codex --scope export
controlkeel plugin export codex
```

## 4. Required QA Evidence

For every defect, capture:

- operating system and version
- install channel used: Homebrew, npm, release installer, or source checkout
- `controlkeel version`
- host version, if applicable
- exact command run
- expected result
- actual result
- relevant logs or stderr
- generated file tree or specific files
- screenshots for browser flows

When reporting, include whether the problem is:

- blocking
- functional but incorrect
- docs mismatch
- packaging/release issue
- environment-specific

## 5. Recommended QA Environment

Baseline tools:

- `git`
- `node`
- `npm`
- `jq`
- a browser

Useful optional hosts:

- Claude Code
- Codex CLI
- OpenCode
- VS Code
- GitHub Copilot
- Cursor
- Cline
- Windsurf
- Continue
- Goose
- Kiro
- Pi
- Augment / Auggie CLI
- Gemini CLI
- Amp
- Aider

Recommended working pattern:

```bash
export CK_QA_ROOT="$(mktemp -d)"
cd "$CK_QA_ROOT"
mkdir governed-app
cd governed-app
git init
echo "# qa" > README.md
git add README.md
git commit -m "init"
```

## 6. Product Surface Map

Use this as the top-level checklist.

### Core local product

- CLI
- local web app
- governed project binding
- local stdio MCP server

### Governance and evidence

- findings
- findings translation
- approvals
- proofs
- audit logs
- release readiness
- progress
- pause and resume
- defensive-security workflow phases, disclosure redaction, and cyber access mode gating

### Bundle and integration delivery

- skills
- native host companions
- plugins
- extensions
- hooks
- commands
- agents/subagents
- runtime exports

### Remote and machine-facing surfaces

- hosted MCP
- A2A
- service accounts
- ACP registry metadata
- proxy endpoints

### Advanced product areas

- benchmarks
- policy training and promotion
- deployment advisor
- cost optimizer
- sandboxes
- outcomes
- webhooks
- policy sets
- worker polling

## 7. Core Smoke Test

Run this first on every release candidate.

### 7.1 Install and boot

Validate one or more install channels:

```bash
brew tap aryaminus/controlkeel && brew install controlkeel
controlkeel version
```

```bash
npm i -g @aryaminus/controlkeel
controlkeel version
```

Expected:

- binary installs successfully
- `controlkeel version` prints a real release version
- version matches the expected release tag

### 7.2 Start the app

```bash
controlkeel
```

Expected:

- process stays up
- local app loads
- browser routes respond without server errors

Check these routes:

- `/start`
- `/missions/:id` after creating work
- `/findings`
- `/proofs`
- `/benchmarks`
- `/policies`
- `/skills`
- `/ship`
- `/deploy`

### 7.3 First-run setup

Inside a temp repo:

```bash
controlkeel setup
```

Expected:

- the command succeeds from the repo root or a nested subdirectory
- output includes:
  - resolved `Project root: ...`
  - `Detected hosts: ...`
  - `Provider source: ...`
  - `Core loop: ck_context -> ck_validate -> ck_review_submit/ck_finding -> ck_budget/ck_route/ck_delegate`
- recommended next steps are actionable
- a governed project binding is created

Expected files:

- `controlkeel/project.json`
- `controlkeel/bin/controlkeel-mcp`
- `.gitignore` includes `/controlkeel`

If you want to validate the explicit low-level bootstrap/init path separately, also run:

```bash
controlkeel bootstrap
controlkeel init
```

Then run:

```bash
controlkeel status
controlkeel findings
controlkeel skills list
controlkeel help
```

Expected:

- commands return successfully
- guided help is usable and routes topical questions correctly

## 8. Local MCP Validation

ControlKeel must expose a working local stdio MCP server.

### 8.1 MCP bootstrap

After `controlkeel setup` or `controlkeel init`, validate:

```bash
test -x controlkeel/bin/controlkeel-mcp
```

### 8.2 MCP handshake and tools/list

Use a framed stdio probe:

```bash
node -e 'const init=JSON.stringify({jsonrpc:"2.0",id:1,method:"initialize",params:{protocolVersion:"2024-11-05",capabilities:{},clientInfo:{name:"ck-qa",version:"1.0"}}}); const list=JSON.stringify({jsonrpc:"2.0",id:2,method:"tools/list",params:{}}); process.stdout.write(`Content-Length: ${Buffer.byteLength(init)}\r\n\r\n${init}`); process.stdout.write(`Content-Length: ${Buffer.byteLength(list)}\r\n\r\n${list}`);' | ./controlkeel/bin/controlkeel-mcp
```

Expected tools should include:

- `ck_context`
- `ck_validate`
- `ck_finding`
- `ck_budget`
- `ck_route`
- `ck_delegate`
- `ck_skill_list`
- `ck_skill_load`

If the build exposes extended tools, note them too, but the core tools above must be present.

### 8.3 Failure cases

Validate:

- running MCP outside a governed repo
- broken project binding
- bad stdin payload

Expected:

- errors are explicit
- no hanging process without useful feedback

## 9. Governance, Findings, Reviews, and Proofs

This is the core product value. Test it deeply.

### 9.1 Create intentional bad changes

Ask a host or manually create one of these patterns:

- hardcoded API key
- SQL string concatenation
- unsafe `innerHTML`
- intentionally risky dependency report through Socket

### 9.2 Findings lifecycle

Run:

```bash
controlkeel findings
controlkeel findings translate
controlkeel status
```

Expected:

- findings appear
- severity is reasonable
- translated output is plain English
- blocked work is shown as blocked

### 9.3 Review flows

Validate:

```bash
controlkeel review diff --base HEAD~1 --head HEAD
controlkeel review pr --stdin < patch.diff
controlkeel review socket --report socket-report.json
```

Expected:

- review command accepts input
- findings and review output match the submitted material
- high-severity Socket issues are surfaced as dependency-risk findings

### 9.4 Plan review lifecycle

Create a plan file:

```bash
cat > plan.md <<'EOF'
# Plan
1. Add a test route
2. Add a dangerous SQL path
3. Validate the result
EOF
```

Submit and process it:

```bash
controlkeel review plan submit --body-file plan.md --submitted-by qa --json
controlkeel review plan open --id <review_id> --json
controlkeel review plan respond <review_id> --decision approved --feedback-notes "qa pass" --json
controlkeel review plan wait --id <review_id> --json
```

Expected:

- submit returns `review.id`
- open returns browser URL or current review state
- respond persists the decision
- wait reflects the final state

### 9.5 Proofs and audit evidence

Validate:

```bash
controlkeel proofs
controlkeel proof <id>
controlkeel audit-log <session-id>
controlkeel release-ready --session-id <id>
```

Expected:

- proofs exist after governed work
- proof details are readable
- audit log exports successfully
- release readiness reflects findings and proof state

## 10. Web App Validation

Open the web app and validate the user-facing product, not just the backend.

### 10.1 Route coverage

Validate that these surfaces load and behave:

- `/start`: onboarding and intent intake
- `/missions/:id`: mission control
- `/findings`: findings browser
- `/proofs`: proof browser
- `/benchmarks`: suite and run browser
- `/policies`: policy artifact view
- `/skills`: target matrix and export/install surface
- `/ship`: deploy-readiness and metrics
- `/deploy`: deployment advisor

### 10.2 What to check on each page

Check:

- page loads without server error
- empty state is reasonable
- page becomes useful after a session exists
- links and actions work
- copy matches the actual product behavior

Capture screenshots when the page is wrong but the backend is technically working.

## 11. Skills, Hooks, Plugins, Extensions, and Bundles

This is where ControlKeel proves host support.

### 11.1 Catalog and diagnostics

Run:

```bash
controlkeel skills list
controlkeel skills validate
controlkeel skills doctor
```

Expected:

- catalog lists real targets
- diagnostics do not contradict generated output
- diagnostics catch weak trigger headers, missing negative boundaries, and missing workflow / output / examples sections for custom skills
- diagnostics warn when a custom skill becomes a large monolith without routing detailed material through `references/` or companion files
- invalid or unsupported states are explained clearly

### 11.2 Export validation

Run a representative export set:

```bash
controlkeel skills export --target codex --scope export
controlkeel skills export --target opencode-native --scope export
controlkeel skills export --target pi-native --scope export
controlkeel skills export --target cline-native --scope export
controlkeel plugin export codex
controlkeel plugin export claude
controlkeel plugin export copilot
controlkeel plugin export openclaw
controlkeel plugin export augment
controlkeel runtime export devin
controlkeel runtime export warp-oz
controlkeel runtime export open-swe
controlkeel runtime export executor
controlkeel runtime export virtual-bash
```

Expected:

- bundle is written under `controlkeel/dist/<target>/`
- manifest files exist
- generated files match the target’s expected surface
- package versions match `controlkeel version` for published npm companions

### 11.3 Install validation

Run representative installs:

```bash
controlkeel skills install --target codex --scope project
controlkeel skills install --target cursor-native --scope project
controlkeel plugin install codex --scope project
controlkeel plugin install claude --scope user
```

Expected:

- files land in the correct user or project location
- rerunning install is safe
- stale assets update cleanly

## 12. Host Integration Matrix

For each host below, validate:

1. `controlkeel setup`
2. `controlkeel attach <host>` or the documented direct-install path
3. confirm the setup output resolved the intended project root when run from nested directories
4. expected files are generated
5. MCP config points at ControlKeel
6. commands, hooks, skills, agents, or extensions are present as claimed
7. if the host is installed locally, the host can see the generated integration

If the host is **not** installed, validate export/install artifacts and mark runtime validation as blocked by environment.

### 12.1 First-class host adapters

| Host | Primary validation command | Must generate or install |
| --- | --- | --- |
| Claude Code | `controlkeel attach claude-code` | `.claude/skills`, `.claude/agents`, plugin bundle |
| GitHub Copilot | `controlkeel attach copilot` | `.github/skills`, `.github/agents`, `.github/commands`, `.vscode/mcp.json` |
| OpenCode | `controlkeel attach opencode` | `.opencode/skills`, `.opencode/plugins`, `.opencode/agents`, `.opencode/commands`, `.opencode/mcp.json`, `.agents/skills` |
| Augment / Auggie CLI | `controlkeel attach augment` | `.augment/skills`, `.augment/agents`, `.augment/commands`, `.augment/rules`, `.augment/mcp.json`, local plugin bundle |
| Pi | `controlkeel attach pi` | `.pi/controlkeel.json`, `.pi/commands`, `.pi/mcp.json`, `pi-extension.json`, `PI.md` |
| VS Code | `controlkeel attach vscode` | `.github/skills`, `.github/agents`, `.vscode/mcp.json`, `.vscode/extensions.json`, companion `.vsix` path |
| Codex CLI | `controlkeel attach codex-cli` | `.codex/skills`, `.agents/skills`, `.codex/config.toml`, `.codex/hooks.json`, `.codex/hooks`, `.codex/agents`, `.codex/commands` |

### 12.2 Broader attach targets

| Host | Primary validation command | Must generate or install |
| --- | --- | --- |
| Cline | `controlkeel attach cline` | `.cline/skills`, `.clinerules`, `.cline/commands`, `.cline/hooks`, MCP config |
| Cursor | `controlkeel attach cursor` | `.agents/skills`, `.cursor/skills`, `.cursor/rules`, `.cursor/commands`, `.cursor/agents`, `.cursor/background-agents`, `.cursor/hooks.json`, `.cursor/hooks`, `.cursor/mcp.json`, `.cursor-plugin/` |
| Windsurf | `controlkeel attach windsurf` | `.windsurf/rules`, `.windsurf/commands`, `.windsurf/workflows`, `.windsurf/hooks`, `.windsurf/hooks.json`, `.windsurf/mcp.json` |
| Continue | `controlkeel attach continue` | `.continue/prompts`, `.continue/commands`, `.continue/mcpServers/controlkeel.yaml`, `.continue/mcp.json` |
| Letta Code | `controlkeel attach letta-code` | `.agents/skills`, `.letta/settings.json`, `.letta/hooks`, `.letta/controlkeel-mcp.sh`, `.letta/README.md`, `.mcp.json` |
| Roo Code | `controlkeel attach roo-code` | `.roo/skills`, `.roo/rules`, `.roo/commands`, `.roo/guidance`, `.roomodes` |
| Goose | `controlkeel attach goose` | `.goosehints`, workflow recipes, Goose commands, extension config |
| Kiro | `controlkeel attach kiro` | `.kiro/hooks`, `.kiro/steering`, `.kiro/settings`, `.kiro/commands`, `.kiro/mcp.json` |
| Amp | `controlkeel attach amp` | `.amp/plugins`, `.agents/skills/controlkeel-governance`, `.amp/commands`, `.amp/package.json` |
| Gemini CLI | `controlkeel attach gemini-cli` | `gemini-extension.json`, `.gemini/commands`, `skills/`, `GEMINI.md`, extension README |
| Aider | `controlkeel attach aider` | `AIDER.md`, `.aider.conf.yml`, `.aider/commands/controlkeel-review.md` |
| Hermes Agent | `controlkeel attach hermes-agent` | `.hermes/skills`, `.hermes/mcp.json` |
| OpenClaw | `controlkeel attach openclaw` | workspace or managed skills plus OpenClaw config |
| Factory Droid | `controlkeel attach droid` | `.factory/skills`, `.factory/droids`, `.factory/commands`, `.factory/mcp.json` |
| Forge | `controlkeel attach forge` | ACP companion plus MCP fallback files |

### 12.3 Direct install paths

Validate these separately from `attach`:

| Surface | Validation command |
| --- | --- |
| Skills.sh collection install | `npx skills add https://github.com/aryaminus/controlkeel` |
| Skills.sh single-skill install | `npx skills add https://github.com/aryaminus/controlkeel --skill controlkeel-governance` |
| OpenCode npm companion | add `"plugin": ["@aryaminus/controlkeel-opencode"]` to `opencode.json` and confirm `mcp.controlkeel` uses a local command array |
| Pi npm extension | `pi install npm:@aryaminus/controlkeel-pi-extension` |
| Pi short form | `pi -e npm:@aryaminus/controlkeel-pi-extension` |
| VS Code companion | `code --install-extension controlkeel-vscode-companion.vsix` |
| Gemini extension link | `gemini extensions link ./controlkeel/dist/gemini-cli-native` |
| Claude plugin install | `controlkeel plugin install claude` |
| Copilot plugin install | `controlkeel plugin install copilot` |
| Codex plugin install | `controlkeel plugin install codex` |
| OpenClaw plugin install | `controlkeel plugin install openclaw` |
| Factory Droid plugin export | `controlkeel plugin export droid` |
| Augment local plugin bundle | `auggie --plugin-dir ./controlkeel/dist/augment-plugin` |
| Amp skill install | `amp skill add ./controlkeel/dist/amp-native/.agents/skills/controlkeel-governance` |

### 12.4 Host-specific pass criteria

For every host, confirm:

- the attach or install command succeeds
- rerunning it is not destructive
- malformed existing config is handled safely
- config format is correct for the host
- generated command names and skill names are usable
- project-scope and user-scope behavior match the docs
- `--mcp-only` behaves correctly where supported

## 13. Hosted MCP, A2A, Service Accounts, and Registry

### 13.1 Service accounts

Validate:

```bash
controlkeel service-account create --workspace-id 1 --name "qa-mcp" --scopes "mcp:access context:read validate:run"
controlkeel service-account list --workspace-id 1
```

This is the minimal hosted-MCP example used for validation. The broader hosted scope map is documented in [support-matrix.md](support-matrix.md#hosted-mcp).

Expected:

- service account is created
- derived OAuth client id is visible

### 13.2 Hosted MCP

Mint a token and call hosted MCP with that same minimal scope set:

```bash
curl -X POST http://localhost:4000/oauth/token \
  -H "content-type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=<oauth_client_id>" \
  --data-urlencode "client_secret=<service_account_token>" \
  --data-urlencode "resource=mcp" \
  --data-urlencode "scope=mcp:access context:read validate:run"
```

```bash
curl -X POST http://localhost:4000/mcp \
  -H "authorization: Bearer <access_token>" \
  -H "content-type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expected:

- token exchange succeeds
- tools list succeeds only with the right scopes
- missing scopes produce correct authorization failures

### 13.3 A2A

Validate:

- `GET /.well-known/agent-card.json`
- `GET /.well-known/agent.json`
- `POST /a2a`

Expected:

- discovery documents load
- only the documented governed capabilities are advertised

### 13.4 ACP registry

Validate:

```bash
controlkeel registry sync acp
controlkeel registry status acp
```

Expected:

- sync succeeds or fails explicitly
- cached freshness is shown
- registry data enriches targets without changing shipped install behavior

## 14. Provider, Proxy, Runtime, and Execution

### 14.1 Provider brokerage

Validate:

```bash
controlkeel provider list
controlkeel provider show openai
controlkeel provider set-key openai --value "$OPENAI_API_KEY"
controlkeel provider set-base-url openai --value http://127.0.0.1:1234
controlkeel provider set-model openai --value local-model
controlkeel provider default openai
controlkeel provider doctor
```

Expected:

- provider state is visible
- doctor reports usable or missing provider state correctly
- base URL and model overrides work

### 14.2 Proxy endpoints

Validate one OpenAI-style path and one Anthropic-style path if credentials exist:

- `/proxy/openai/{proxy_token}/v1/responses`
- `/proxy/openai/{proxy_token}/v1/chat/completions`
- `/proxy/openai/{proxy_token}/v1/embeddings`
- `/proxy/openai/{proxy_token}/v1/models`
- `/proxy/anthropic/{proxy_token}/v1/messages`
- `/proxy/openai/{proxy_token}/v1/realtime`

Expected:

- ControlKeel proxy URL is generated by the product
- requests pass or fail clearly
- unsupported upstream assumptions are not silently accepted

### 14.3 Runtime exports

Validate:

```bash
controlkeel runtime export devin
controlkeel runtime export warp-oz
controlkeel runtime export open-swe
controlkeel runtime export cloudflare-workers
controlkeel runtime export executor
controlkeel runtime export virtual-bash
```

Expected:

- runtime bundles are created
- bundle docs explain how the runtime should use ControlKeel
- runtime manifests or bootstrap examples match the runtime shape they claim to support

### 14.4 Governed execution

Validate:

```bash
controlkeel agents doctor
controlkeel run task <id> --agent auto
controlkeel run session <id> --agent auto
controlkeel agents monitor
controlkeel pause <task-id>
controlkeel resume <task-id>
```

Expected:

- execution mode is reported honestly as direct, handoff, runtime, or inbound-only
- blocked findings stop execution when they should
- pause and resume preserve task state

### 14.5 Sandboxes

Validate:

```bash
controlkeel sandbox status
controlkeel sandbox config local
```

Expected:

- unavailable adapters are reported clearly
- setting a default adapter works

## 15. Benchmarks, Policies, Deploy, Cost, Outcomes, and Ops

These are not secondary features. They are part of the product and must be validated.

### 15.1 Benchmarks

Validate:

```bash
controlkeel benchmark list
controlkeel benchmark run --help
controlkeel benchmark import <run-id> <subject> <json-file>
controlkeel benchmark export <run-id>
```

Check:

- suites list correctly
- runs persist
- import and export work

### 15.2 Policy artifacts

Validate:

```bash
controlkeel policy list
controlkeel policy train --type router
controlkeel policy show <id>
controlkeel policy promote <id>
controlkeel policy archive <id>
```

Check:

- lifecycle is coherent
- invalid promotions fail clearly

### 15.3 Deployment and cost

Validate:

```bash
controlkeel deploy analyze
controlkeel deploy cost --stack phoenix
controlkeel deploy dns phoenix
controlkeel deploy migration phoenix
controlkeel deploy scaling phoenix
controlkeel cost optimize
controlkeel cost compare --tokens 10000
```

Check:

- analyze detects a plausible stack
- cost output is readable
- platform guidance is generated

### 15.4 Outcomes, progress, memory, and circuit breakers

Validate:

```bash
controlkeel progress
controlkeel memory search risk
controlkeel circuit-breaker status
controlkeel outcome leaderboard
```

Expected:

- commands return useful state or explicit empty-state guidance

### 15.5 Enterprise and CI surfaces

Validate:

```bash
controlkeel policy-set list
controlkeel webhook list
controlkeel graph show <session-id>
controlkeel execute <session-id>
controlkeel worker start --help
```

Expected:

- commands exist and fail clearly when configuration is missing
- help text and behavior match the docs

## 16. Negative Test Cases

Every serious QA pass should include these:

- attach into a repo with malformed existing host config
- attach twice
- switch between `--scope project` and `--scope user`
- attach with `--mcp-only`
- no provider configured
- invalid provider URL
- invalid review id
- missing service-account scope
- unsupported host not installed
- stale generated bundle after upgrade
- missing browser in remote environment

Expected:

- no destructive behavior
- clear errors
- docs and product behavior stay aligned

## 17. Pass/Fail Criteria

A feature passes when:

- the command or UI action succeeds
- the generated artifacts match the documented surface
- the behavior is truthful
- the failure mode is explicit and recoverable
- the docs do not over-claim support

A feature fails when:

- documented files are missing
- generated config is malformed for the host
- a publish/install surface uses the wrong version
- browser review, MCP, or hosted auth flows do not complete as documented
- ControlKeel claims support that cannot actually be exercised

## 18. Bug Report Format for Codex

Use this exact structure when handing an issue to Codex:

```text
Title:
Short description of the failure

Environment:
- OS:
- Install channel:
- ControlKeel version:
- Host and version:

Area:
- CLI / Web / MCP / Hosted MCP / A2A / Skills / Plugin / Extension / Hook / Review / Findings / Proofs / Runtime / Provider / Release

Command(s):
Exact command(s) run

Expected:
What should have happened

Actual:
What happened instead

Evidence:
- stderr/stdout
- screenshots
- generated files
- relevant JSON or config

Notes:
- reproducible always or intermittent
- regression from prior version or not
```

## 19. Final QA Deliverable

At the end of a QA pass, produce:

- release version tested
- install channels tested
- hosts tested end-to-end
- hosts tested artifact-only
- failures found
- docs mismatches found
- blocked items due to missing environment
- recommendation: ship / ship with caveats / do not ship

This document is the procedure. The actual current state of validation should be recorded in [integration-validation-checklist.md](integration-validation-checklist.md).
