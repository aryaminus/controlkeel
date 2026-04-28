# ControlKeel Getting Started

This is the shortest path from first install to first governed finding.

ControlKeel is the control tower that turns agent-generated work into secure, scoped, validated, production-ready delivery. ControlKeel turns agent output into production engineering. The default path is built for serious solo builders and tiny agent-heavy teams, not for enterprise admin workflows first.

Agent output is cheap. Reviewability, security, release safety, and cost control are not. ControlKeel exists to govern that layer, not replace the coding model underneath it.

That also makes ControlKeel the recovery path when another generator already touched the repo: bootstrap the project, surface the production boundary, and use findings, proofs, and governed proxy flows to get back to a reviewable state.

It is not another IDE, another coding model, a prompt marketplace, or post-hoc code review only. The first-run path gets you into the live proof console loop quickly:

- Mission Control for active task state and approvals
- Proof Browser for immutable evidence bundles
- Ship Dashboard for governed outcome metrics
- Benchmarks for comparative evidence

The onboarding model is deliberately **occupation-first**. Users describe what kind of work they do, not which compliance framework they think applies. ControlKeel uses that answer to pick the domain pack, interview language, and governance posture behind the scenes.

The governed delivery lifecycle is:

- intent intake
- execution brief
- execution posture
- task graph and routing
- validation and findings
- proof bundles
- ship metrics
- benchmarks

The main stewardship surfaces for that lifecycle are `/ship` and `/benchmarks`.
`/ship` now also surfaces autonomy mix, outcome shape, and the current improvement-loop focus across recent governed sessions.

If you are using CK for defensive security work, start with the `security` domain pack. That gives you the defender mission template, structured vulnerability lifecycle metadata, disclosure-aware proof bundles, and cyber access mode defaults. The dedicated guide is [defensive-security-with-controlkeel.md](defensive-security-with-controlkeel.md).

Execution posture is how CK keeps the harness honest:

- use the read-only virtual workspace for repo exploration before provisioning execution
- keep durable state in typed CK surfaces such as memory, proofs, traces, and outcomes instead of treating files as the only durable interface
- prefer typed or code-mode execution for large API and MCP-style tool surfaces when the host supports it
- keep shell as the broad fallback surface for repo mutation, package commands, and test runs

If you want the architecture map behind that lifecycle, read [control-plane-architecture.md](control-plane-architecture.md).

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

Change into the project you want to govern and run the first-run setup flow:

```bash
controlkeel setup
```

That bootstraps the governed project binding, detects likely local hosts, shows provider state, and suggests the next attach or runtime-export commands.

Then attach an agent. Start with the strongest active supported path for the current workspace rather than attaching every detected host up front. If you want the fastest first-run path today, OpenCode is now a blessed target:

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
mix ck.setup
mix ck.attach opencode
mix ck.init
```

For exact companion package names and direct-install commands, use [direct-host-installs.md](direct-host-installs.md).

Bootstrap or init writes:

- `controlkeel/project.json`
- `controlkeel/bin/controlkeel-mcp`
- `/controlkeel` in `.gitignore`

ControlKeel registers a local MCP server using the generated project-local wrapper so the attached client can call back into the governed runtime.

Important setup rule:

- agent install scope can be user/global for some clients
- governed project binding stays project-local by design so each repo keeps its own proofs, policy context, and MCP wrapper

User-intervention checkpoints:

- if the host blocks repo-local config or MCP loading until the workspace is trusted, stop and ask the user to trust the repo/workspace first
- if the host requires a restart after attach or plugin changes, stop and ask the user to restart it before continuing validation
- if `controlkeel provider doctor` still resolves to heuristic mode and the workspace needs model-backed CK features, ask the user to confirm a provider bridge, CK-owned provider profile, or local Ollama path
- if a plan review cannot auto-wait to `approved`, ask the user for explicit approval and record that instead of pretending the gate is cleared

The smallest dependable verification loop after attach is:

```bash
controlkeel attach doctor
controlkeel provider doctor
controlkeel status
controlkeel findings
```

Then run the host-specific MCP check, such as `opencode mcp list` for OpenCode or the relevant host-native MCP inspection command.

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

If you want to use an OpenAI-compatible local or hosted backend instead of OpenAI directly:

```bash
controlkeel provider set-base-url openai --value http://127.0.0.1:1234
controlkeel provider set-model openai --value local-model
controlkeel provider default openai
```

This is the path for vLLM, SGLang, LM Studio, Hugging Face Inference Providers, and Codestral-compatible endpoints. CK accepts base URLs with or without a trailing `/v1`.

For local-model experimentation, treat the harness as part of the evaluation target, not as a transparent wrapper. A hosted coding harness, prompt format, or tool-call contract does not automatically transfer cleanly to a local backend just because the endpoint is OpenAI-compatible. The dependable path is:

- start with a simple console-first loop
- verify the actual request/response and tool behavior of the local runtime you are using
- benchmark that concrete setup through CK before making product or quality claims

If `controlkeel provider doctor` still reports `heuristic`, CK governance and MCP flows still work, but advisory review and other model-backed CK features remain limited until you confirm one of the provider paths above.

CK now treats routed and custom gateway paths as explicit trust boundaries rather than transparent drop-ins. `controlkeel provider show` and `controlkeel provider doctor` report:

- trust boundary, such as `direct_provider`, `openai_compatible_gateway`, `api_router_intermediary`, or `host_managed_agent_bridge`
- intermediary risk, such as `low`, `medium`, or `high`
- integrity posture, which helps explain whether CK is talking to a direct provider path or to something that can observe and rewrite tool-call payloads in the middle

For high-risk or routed paths, prefer:

- fail-closed validation for shell, installer, and package-execution work
- append-only request and response evidence logging
- direct provider paths for sensitive coding, deploy, and security sessions when possible

If you do not have keys and are not running a local model, ControlKeel still works for:

- MCP tools and governed attachments
- governance and findings
- proof bundles and audit trail
- skills and benchmark flows

You can also understand support by **integration mechanism**, not only by client name:

- **Native attach** for clients with first-class MCP config and companion installs
- **Governed proxy** for tools that can point at OpenAI- or Anthropic-compatible endpoints
- **Runtime export** for headless or governed outer-loop systems such as Devin, Open SWE, Executor, and the CK-owned `virtual-bash` recipe
- **Provider-only** for CK-owned or local backends such as Ollama, vLLM, SGLang, LM Studio, Hugging Face, and Codestral-compatible endpoints
- **Fallback governance** for unsupported tools after bootstrap using `controlkeel watch`, `controlkeel findings`, proof flows, and `ck_validate`

That fallback path is the current project-rescue story. It is honest support, not a fake claim that every external tool has native ControlKeel attachment.

In that mode, model-backed features such as advisory review and intent compilation either degrade to heuristics or return explicit capability guidance.

The LLM **advisory** layer (extra review beyond pattern matchers) only runs when a provider is available. The HTTP validate API and MCP validate tool include an **`advisory`** field describing whether advisory ran or was skipped—see [autonomy-and-findings.md](autonomy-and-findings.md) for how findings relate to human review.

Other common attach targets include `claude-code`, `codex-cli`, `cline`, `cursor`, `windsurf`, `continue`, `letta-code`, `kiro`, `amp`, `gemini-cli`, `copilot`, `vscode`, `goose`, `roo-code`, `hermes-agent`, `openclaw`, `droid`, and `forge`.

For the full host truth, use the canonical [support-matrix.md](support-matrix.md), the install-focused [direct-host-installs.md](direct-host-installs.md), the behavior model in [agent-integrations.md](agent-integrations.md), or the docs map in [README.md](README.md). You can also open `/skills` in the local app.

If you use Cline, the attach flow is first-class for MCP, skills, rules, and workflows, but CK still needs its own provider profile or local Ollama for CK-internal model work because Cline's provider secrets are not exposed as a documented bridge.

## 3a. OpenCode quick path

For OpenCode specifically:

```bash
controlkeel attach opencode
controlkeel attach doctor
controlkeel status
opencode mcp list
```

This writes the MCP configuration into the OpenCode config location and also generates the portable instruction bundle ControlKeel uses for MCP-plus-instructions targets.

Validation tip: in `~/.config/opencode/opencode.json`, ensure `mcp.controlkeel.enabled` is `true`. If OpenCode shows `controlkeel` as disabled while validating unreleased local fixes, rerun the local attach path:

```bash
mix ck.attach opencode
```

ControlKeel now mirrors MCP config to both OpenCode config paths (`~/.config/opencode/opencode.json` and `~/.config/opencode/config.json`) during attach so hosts reading either file stay in sync.

If you still see transient `Not connected` messages immediately after OpenCode startup, wait 2-5 seconds and retry the tool call once. The local MCP server bootstraps Repo/services asynchronously and then stabilizes; a quick retry after startup usually resolves transient boot races.

If `ck_context` or `ck_validate` still report `Not connected` after attach:

```bash
controlkeel attach doctor
controlkeel provider doctor
```

If errors persist, check the OpenCode log at `~/.local/share/opencode/log/*.log` for `service=mcp key=controlkeel` lines and rerun:

```bash
controlkeel attach opencode
controlkeel attach doctor
```

OpenCode now has a native-first integration that writes `.opencode/skills`, `.opencode/plugins`, `.opencode/agents`, `.opencode/commands`, `.opencode/mcp.json`, and `.agents/skills` compatibility copies (using OpenCode's `mcp.controlkeel` local command-array shape). However, it does not currently expose a documented provider bridge the way Claude Code and Codex CLI do, so the usual next-best options for CK model work are:

- keep using heuristic mode for governance-only flows
- add a CK-owned provider profile
- point ControlKeel at a local Ollama model

If you prefer the direct host package path, OpenCode also has a published npm companion. Use [direct-host-installs.md](direct-host-installs.md) for the exact package name and command. `controlkeel attach opencode` remains the recommended path when you want the repo-local MCP wiring, commands, and agent bundle too.

Plan-review tip for OpenCode:

- when using the `submit_plan` tool directly, prefer `submit_plan({ plan: "...", wait_timeout_seconds: 30 })` for predictable wait behavior
- the same timeout can be set globally with `CONTROLKEEL_REVIEW_WAIT_TIMEOUT`
- if the returned payload indicates `waitSkipped: true` or `manualApprovalRequired: true` (for example browser URL missing/unreachable or the browser did not actually open), ask the user for explicit chat approval and record it with `controlkeel review plan respond --id <review_id> --decision approved --feedback-notes "User approved in chat; browser unavailable" --json` (or `ck_review_feedback`) instead of repeatedly waiting

## 3b. Hosted MCP or A2A access for headless clients

The repo-local default is still:

- local stdio MCP through `controlkeel mcp`
- native `controlkeel attach ...` flows for supported clients

Hosted protocol access is for service-account-driven machines and remote clients.

For headless or asynchronous runtimes, the same governed repo can also export runtime bundles directly:

```bash
controlkeel runtime export devin
controlkeel runtime export warp-oz
controlkeel runtime export cloudflare-workers
controlkeel runtime export executor
controlkeel runtime export virtual-bash
```

Use the support matrix for the full shipped runtime catalog. The important distinction is that runtime exports are not fake attach commands: they emit the files and guidance a headless runtime or governed outer loop actually needs.

Create a service account with protocol scopes. The example below is a minimal hosted-MCP token for context and validation; the full hosted scope matrix lives in [support-matrix.md](support-matrix.md#hosted-mcp).

```bash
controlkeel service-account create --workspace-id 1 --name "ci-mcp" --scopes "mcp:access context:read validate:run"
```

The create and list commands print the derived OAuth client id, for example `ck-sa-123`.

Mint a short-lived bearer token for the same minimal scope set:

```bash
curl -X POST http://localhost:4000/oauth/token \
  -H "content-type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=ck-sa-123" \
  --data-urlencode "client_secret=YOUR_SERVICE_ACCOUNT_TOKEN" \
  --data-urlencode "resource=mcp" \
  --data-urlencode "scope=mcp:access context:read validate:run"
```

Then call hosted MCP:

```bash
curl -X POST http://localhost:4000/mcp \
  -H "authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "content-type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Hosted discovery is available at:

- `/.well-known/oauth-protected-resource/mcp`
- `/.well-known/oauth-protected-resource`
- `/.well-known/oauth-authorization-server`

Minimal A2A discovery and message routing are available at:

- `/.well-known/agent-card.json`
- `/.well-known/agent.json`
- `POST /a2a`

That A2A layer only exposes the governed CK capabilities `ck_context`, `ck_validate`, `ck_finding`, `ck_budget`, `ck_route`, and `ck_delegate`; guarded code execution remains local/stdio MCP only.

ACP registry discovery is optional. To refresh or inspect the local cache:

```bash
controlkeel registry sync acp
controlkeel registry status acp
```

The registry cache only enriches the shipped catalog in `/skills` and `GET /api/v1/skills/targets`. It never changes attach/install behavior on its own.

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
- Packaged local mode is a real product lane. Cloud/headless mode exists partially today, and broader team / enterprise platform work remains a later branch.
