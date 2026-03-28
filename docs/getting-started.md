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
- task graph and routing
- validation and findings
- proof bundles
- ship metrics
- benchmarks

The main stewardship surfaces for that lifecycle are `/ship` and `/benchmarks`.

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

If you want to use an OpenAI-compatible local or hosted backend instead of OpenAI directly:

```bash
controlkeel provider set-base-url openai --value http://127.0.0.1:1234
controlkeel provider set-model openai --value local-model
controlkeel provider default openai
```

This is the path for vLLM, SGLang, LM Studio, Hugging Face Inference Providers, and Codestral-compatible endpoints. CK accepts base URLs with or without a trailing `/v1`.

If you do not have keys and are not running a local model, ControlKeel still works for:

- MCP tools and governed attachments
- governance and findings
- proof bundles and audit trail
- skills and benchmark flows

You can also understand support by **integration mechanism**, not only by client name:

- **Native attach** for clients with first-class MCP config and companion installs
- **Governed proxy** for tools that can point at OpenAI- or Anthropic-compatible endpoints
- **Runtime export** for headless systems such as Devin and Open SWE
- **Provider-only** for CK-owned or local backends such as Ollama, vLLM, SGLang, LM Studio, Hugging Face, and Codestral-compatible endpoints
- **Fallback governance** for unsupported tools after bootstrap using `controlkeel watch`, `controlkeel findings`, proof flows, and `ck_validate`

That fallback path is the current project-rescue story. It is honest support, not a fake claim that every external tool has native ControlKeel attachment.

In that mode, model-backed features such as advisory review and intent compilation either degrade to heuristics or return explicit capability guidance.

The LLM **advisory** layer (extra review beyond pattern matchers) only runs when a provider is available. The HTTP validate API and MCP validate tool include an **`advisory`** field describing whether advisory ran or was skipped—see [autonomy-and-findings.md](autonomy-and-findings.md) for how findings relate to human review.

Other supported attach commands:

- `controlkeel attach claude-code`
- `controlkeel attach codex-cli`
- `controlkeel attach cline`
- `controlkeel attach vscode`
- `controlkeel attach copilot`
- `controlkeel attach cursor`
- `controlkeel attach windsurf`
- `controlkeel attach continue`
- `controlkeel attach aider`

For the full native skills / plugin matrix, see [agent-integrations.md](agent-integrations.md) and the canonical [support-matrix.md](support-matrix.md), or open `/skills` in the local app.

If you use Cline, the attach flow is first-class for MCP, skills, rules, and workflows, but CK still needs its own provider profile or local Ollama for CK-internal model work because Cline's provider secrets are not exposed as a documented bridge.

## 3b. Hosted MCP or A2A access for headless clients

The repo-local default is still:

- local stdio MCP through `controlkeel mcp`
- native `controlkeel attach ...` flows for supported clients

Hosted protocol access is for service-account-driven machines and remote clients.

Create a service account with protocol scopes:

```bash
controlkeel service-account create --workspace-id 1 --name "ci-mcp" --scopes "mcp:access context:read validate:run"
```

The create and list commands print the derived OAuth client id, for example `ck-sa-123`.

Mint a short-lived bearer token:

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

That A2A layer only exposes the governed CK capabilities `ck_context`, `ck_validate`, `ck_finding`, `ck_budget`, and `ck_route`.

ACP registry discovery is optional. To refresh or inspect the local cache:

```bash
controlkeel registry sync acp
controlkeel registry status acp
```

The registry cache only enriches the shipped catalog in `/skills` and `GET /api/v1/skills/targets`. It never changes attach/install behavior on its own.

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
- Packaged local mode is a real product lane. Cloud/headless mode exists partially today, and broader team / enterprise platform work remains a later branch.
