# ControlKeel

ControlKeel is the control plane that turns AI coding into production engineering. It sits above Claude Code, Codex, Cursor, Bolt, Replit, and other agent tools to enforce validation, budgets, findings review, and governed execution.

Every piece of code an AI agent proposes is scanned before it runs. Hardcoded secrets, SQL injection, unsafe shell, HIPAA violations — blocked before they land in your repo. You see everything in a live mission dashboard and approve or reject findings from the web UI, CLI, or REST API.

---

## Quick Start

### Packaged Binary

```bash
# 1. Start the local governance server
controlkeel

# 2. In the project you want to govern
controlkeel init --industry health --agent claude --budget 20

# 3. Register as Claude Code's local MCP server
controlkeel attach claude-code

# 4. Ask Claude Code to write something risky (hardcoded key, SQL injection)
# ControlKeel intercepts it via MCP before execution

# 5. Review findings
controlkeel findings
controlkeel watch   # stream live as they happen
```

### From Source

```bash
git clone <repo>
cd controlkeel
mix setup            # deps + database
mix phx.server       # http://localhost:4000

# In your project
mix ck.init --industry health --agent claude --budget 20
mix ck.attach claude-code
mix ck.watch
```

---

## How It Works

```
Your AI agent (Claude Code / Codex / Cursor)
        │  MCP call: ck_validate
        ▼
  ControlKeel Policy Engine
    ├── FastPath scanner   (<5ms, Elixir patterns + entropy)
    ├── Semgrep SAST       (language-aware AST rules)
    └── Budget enforcement (session + daily rolling limits)
        │
        ├── ALLOW  → agent continues
        ├── WARN   → agent continues, finding logged
        └── BLOCK  → agent halted, finding surfaced in dashboard
                          │
                  Mission Control UI (http://localhost:4000/missions/:id)
                          │
                  Human reviews finding → Approve / Reject / Escalate
```

### Policy Packs

Rules are organised into packs, loaded from `priv/policy_packs/`:

| Pack | When active | Example rules |
|------|-------------|---------------|
| **Baseline — Secrets** | Always | Hardcoded API keys, AWS access keys, high-entropy tokens |
| **Baseline — Injection** | Always | SQL injection, eval/exec, unsafe HTML |
| **Cost** | Always | Budget overrun warnings |
| **Software — Code hygiene** | Software projects | Debug endpoints, CORS wildcard, console.log sensitive data |
| **Healthcare** | `industry: health` | HIPAA data logging, unencrypted PHI fields |
| **Finance** | `industry: fintech` | PCI DSS, plaintext card numbers |
| **Education** | `industry: edu` | FERPA, student data exposure |

View all active packs and rules at [/policies](http://localhost:4000/policies).

---

## Web UI

| Route | What you see |
|-------|-------------|
| `/start` | Launch wizard — describe your project, set a daily budget, pick an agent |
| `/missions/:id` | Mission Control — real-time findings feed, task progress, compliance score, approve/reject |
| `/findings` | All findings across sessions — filter by severity, status, category |
| `/policies` | Active policy packs, rule counts, budget limits per session |
| `/ship` | Install-to-first-finding funnel, session performance metrics |

---

## CLI

### Packaged binary

```bash
controlkeel                             # start governance server
controlkeel init [options]              # initialise project
controlkeel attach claude-code          # register MCP server with Claude Code
controlkeel status                      # current session status
controlkeel findings [--severity high]  # list findings
controlkeel approve <finding-id>        # approve a finding
controlkeel watch [--interval 2000]     # live stream of findings + budget
controlkeel mcp [--project-root /path]  # run MCP server (stdio)
```

### Source (mix tasks)

```bash
mix ck.init [options]
mix ck.attach claude-code
mix ck.status
mix ck.findings [--severity high] [--status open]
mix ck.approve 12
mix ck.watch [--interval 2000]
mix ck.mcp [--project-root /abs/path]
mix ck.demo [--host http://localhost:4000]
```

`mix ck.init` options:

| Flag | Default | Description |
|------|---------|-------------|
| `--industry` | `saas` | `health`, `fintech`, `edu`, `saas`, `general` |
| `--agent` | `claude` | `claude`, `cursor`, `codex`, `bolt`, `replit` |
| `--idea` | — | One-line project description |
| `--features` | — | Comma-separated feature list |
| `--budget` | `30` | Daily AI spend limit in USD |
| `--users` | — | Who uses this product |
| `--data` | — | What data it handles |
| `--project-name` | — | Custom session title |

---

## MCP Integration

ControlKeel exposes four MCP tools over stdio (JSON-RPC 2.0).

### `ck_validate` — scan before executing

```json
{
  "content": "ANTHROPIC_API_KEY = 'sk-ant-...'",
  "path": "app/config.py",
  "kind": "code",
  "session_id": 1
}
```

Returns: `{ "allowed": false, "decision": "block", "summary": "...", "findings": [...] }`

### `ck_context` — fetch session risk + budget

```json
{ "session_id": 1 }
```

Returns: risk tier, compliance profile, open findings summary, budget remaining.

### `ck_finding` — persist a finding and get its ruling

```json
{
  "session_id": 1,
  "category": "credential",
  "severity": "critical",
  "rule_id": "secret.aws_access_key",
  "plain_message": "Hardcoded AWS access key detected in config.py"
}
```

Returns: `{ "finding_id": 42, "status": "blocked", "requires_human": true }`

### `ck_budget` — estimate or commit cost

```json
{
  "session_id": 1,
  "mode": "commit",
  "estimated_cost_cents": 15,
  "provider": "anthropic",
  "model": "claude-sonnet-4-6",
  "input_tokens": 1200,
  "output_tokens": 400
}
```

**Connecting manually:**

```bash
mix ck.mcp --project-root /path/to/your/project
```

Add to `~/.claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "controlkeel": {
      "command": "/path/to/your/project/controlkeel/bin/controlkeel-mcp"
    }
  }
}
```

---

## REST API

All endpoints return JSON. No authentication in local mode.

```
GET  /api/v1/sessions                        list sessions
POST /api/v1/sessions                        create session
GET  /api/v1/sessions/:id                    session detail (includes tasks + findings)
POST /api/v1/sessions/:session_id/tasks      create task
POST /api/v1/validate                        validate content (same as ck_validate)
GET  /api/v1/findings                        list findings (filters: session_id, severity, status)
POST /api/v1/findings/:id/action             approve | reject | escalate
GET  /api/v1/budget                          global or per-session budget summary
```

Example — validate content:

```bash
curl -s http://localhost:4000/api/v1/validate \
  -H "Content-Type: application/json" \
  -d '{"content": "api_key = \"AKIAIOSFODNN7EXAMPLE\"", "kind": "code"}' | jq .
```

```json
{
  "allowed": false,
  "decision": "block",
  "summary": "1 critical finding",
  "findings": [
    {
      "rule_id": "secret.aws_access_key",
      "severity": "critical",
      "plain_message": "AWS access key detected. Rotate immediately."
    }
  ]
}
```

---

## Configuration

Set via environment variables (read at runtime):

```bash
# Server
PORT=4000
PHX_HOST=localhost

# LLM providers (used for intent compilation in onboarding)
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
OPENROUTER_API_KEY=...
OLLAMA_HOST=http://localhost:11434

# Scanner
CONTROLKEEL_SEMGREP_BIN=semgrep         # path to semgrep binary (optional, enables SAST)

# HTTP proxy (optional — govern OpenAI/Anthropic calls via proxy)
CONTROLKEEL_PROXY_OPENAI_UPSTREAM=https://api.openai.com
CONTROLKEEL_PROXY_ANTHROPIC_UPSTREAM=https://api.anthropic.com

# Intent compiler
CONTROLKEEL_INTENT_DEFAULT_PROVIDER=anthropic  # or openai, openrouter, ollama
CONTROLKEEL_INTENT_ANTHROPIC_MODEL=claude-sonnet-4-6
```

For local development, none of these are required. The scanner works without an LLM; onboarding falls back to heuristic compilation.

---

## Demo

Run the built-in demo to see the full detection loop without any setup:

```bash
mix ck.demo
```

This creates a healthcare session, submits Python code containing a hardcoded AWS key + SQL injection, and prints all findings with URLs to review them.

---

## Development

```bash
mix setup         # install deps, create + migrate DB
mix phx.server    # start with live reload
mix test          # 114 tests, 0 failures
mix precommit     # compile (warnings-as-errors) + format + test
```

Database is SQLite (no external services needed).

---

## Packaging

Single-binary builds via [Burrito](https://github.com/burrito-elixir/burrito):

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release

# Target-specific
BURRITO_TARGET=macos_silicon MIX_ENV=prod mix release
BURRITO_TARGET=linux         MIX_ENV=prod mix release
BURRITO_TARGET=windows       MIX_ENV=prod mix release
```

Output: `burrito_out/controlkeel` (or `.exe` on Windows). No Erlang runtime required on the target machine.

---

## Guides

- [Getting started](docs/getting-started.md)
- [Demo script](docs/demo-script.md)
