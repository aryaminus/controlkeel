# Changelog

## v0.1.0 — 2026-03-18

First public release.

### What's included

**Core governance engine**
- Three-tier scanner: FastPath (<5ms Elixir patterns + entropy analysis) → Semgrep SAST (16 rules) → budget enforcement
- Policy packs: Baseline Secrets, Baseline Injection, Cost, Software, Healthcare, Finance, Education
- Per-session and rolling 24h budget enforcement with warn/block decisions
- MCP server (JSON-RPC 2.0 over stdio) with four tools: `ck_validate`, `ck_context`, `ck_budget`, `ck_finding`
- HTTP proxy for OpenAI and Anthropic APIs — scans both request and response content

**Web UI (5 LiveViews)**
- `/start` — Mission launch wizard with domain selection, agent picker, daily budget input
- `/missions/:id` — Real-time mission control with compliance score donut, task list, approve/reject findings
- `/findings` — Cross-session findings browser with severity/status/category filters
- `/policies` — Policy Studio showing active packs, rule counts, session budgets
- `/ship` — Install-to-first-finding funnel metrics

**REST API** (`/api/v1/`)
- Sessions CRUD, task creation, content validation, findings with actions, budget summary

**CLI** (8 commands)
- `init`, `attach`, `status`, `findings`, `approve`, `watch`, `mcp`, `demo`
- Binary packaging via Burrito — no Erlang required on target machine

**Developer experience**
- `mix ck.demo` — end-to-end demo: creates a healthcare session, scans code with hardcoded AWS key + SQL injection, reports findings with dashboard URLs
- `mix ck.watch` / `controlkeel watch` — live stream of findings and budget in the terminal
- 114 tests, 0 failures

### Semgrep rules (16)
SQL injection, XSS sinks, `dangerouslySetInnerHTML`, inline scripts, hardcoded secrets, hardcoded JWT, `eval()`, `subprocess(shell=True)`, `os.system()`, `pickle.loads()`, `curl | bash`, `rm -rf`, prototype pollution, debug mode in prod, open redirect, hardcoded credentials

### What's Phase 2 (not in this release)
- Agent Router (Layer 3) — automatic agent selection by task type
- Memory System (Layer 6) — pgvector semantic memory, episodic records, RL policy tuning
- LLM Advisory scanner — context-aware 3rd tier after FastPath + Semgrep
- Multi-tenant auth — user accounts, org-level sessions, API keys
- Audit Log PDF export
