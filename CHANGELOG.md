# Changelog

## v0.1.24 — 2026-04-06

### What's changed

- Refactor research note and submission payload for clarity and accuracy
- Add research note and benchmark details for ControlKeel governance
- Add ControlKeel benchmarking artifacts and analysis scripts

## v0.1.23 — 2026-04-05

### What's changed

- feat: add Kilo Code integration with native support and enhance documentation
- feat: enhance documentation and tests for skills.sh integration and aliases

## v0.1.22 — 2026-04-05

### What's changed

- docs: update installation documentation with direct host package details and commands
- feat: introduce setup command for bootstrapping ControlKeel and enhance project root resolution

## v0.1.21 — 2026-04-05

### What's changed

- Enhance ControlKeel governance and memory management
- feat: add QA validation guide and update documentation references

## v0.1.20 — 2026-04-03

### What's changed

- Refactor documentation and code for ControlKeel integrations
- feat: add guided help system and enhance help command functionality

## v0.1.19 — 2026-04-03

### What's changed

- feat: enhance Codex CLI integration with config management and installation support

## v0.1.18 — 2026-04-03

### What's changed

- feat: add augment-native and augment-plugin support
- Add annotate and last commands for various skills in ControlKeel
- feat: add explicit review commands and enhance feedback handling in ControlKeel
- Add agent adapters and runtimes for OpenCode, Pi, and VSCode
- Add review lifecycle functionality and associated tests

## v0.1.17 — 2026-04-02

### What's changed

- docs: clarify release installs and bundle coverage

## v0.1.16 — 2026-04-01

### What's changed

- feat: add OpenCode integration support and enhance CLI configuration handling

## v0.1.15 — 2026-04-01

### What's changed

- feat: add new framework adapters and enhance security rules for leak-derived dependencies
- feat: add Socket dependency review command and related tests
- feat: enhance documentation and add security rules for SSRF and dependency hygiene

## v0.1.14 — 2026-04-01

### What's changed

- fix: improve plugin installation error handling and output messages
- docs: update attach commands and release verification checkpoints
- fix: update badge links in README for Release Smoke and Latest Release

## v0.1.13 — 2026-04-01

### What's changed

- fix: specify repository in gh run download command for artifact retrieval

## v0.1.12 — 2026-04-01

### What's changed

- feat: update workflow triggers for Release Smoke and Bump Version processes

## v0.1.11 — 2026-04-01

### What's changed

- feat: implement retry logic for finding successful Release Smoke run in release workflow

## v0.1.10 — 2026-04-01

### What's changed

- feat: rename parameter in Test-TcpPortOpen function for clarity and update references in Test-ProcessListeningPort function
- feat: enhance Test-TcpPortOpen function with null check for connectTask and improved client disposal logic
- feat: add Test-ProcessListeningPort function for enhanced server process checks in release smoke script
- feat: add Test-TcpPortOpen function for improved server connectivity checks in release smoke script
- feat: improve logging in release smoke script by separating stdout and stderr
- feat: add overwrite option to mix release commands in release smoke script
- feat: update release smoke scripts to improve server process handling and error reporting
- feat: improve error handling for daemon startup in release smoke script
- feat: enhance CI workflow, add file overwrite handling, and improve tests for deployment advisor
- feat: update CI workflow and add verification script for required patterns
- feat: remove redundant help command from release smoke script
- feat: finalize governance/docs reconciliation and quality fixes
- feat: enhance cost optimizer and outcome tracker tools with improved handling and new workspace_id defaults
- feat: add comprehensive test suite for deployment advisor, findings translation, and project governance modules
- feat: add MCP tools for cost optimization, outcome tracking, and deployment advisory with updated skill documentation
- feat: implement learning, cost management, deployment guidance, and governance modules to close system gap analysis
- feat: implement deployment advisor with automated infrastructure generation and project monitoring tools
- docs: add pathfinder gap analysis and research documentation
- docs: add documentation for mcptocli integration to agent-integrations.md
- feat: implement OWASP-style classification metrics and add benign baseline benchmark suite
- refactor: update agent support matrix to native integration and simplify README documentation
- feat: upgrade Kiro, Amp, OpenCode, and Gemini-CLI integrations to native-first mode with expanded export and installation support.
- feat: implement pluggable execution sandbox system with E2B, local, and Docker support, and add Gemini proxy capabilities
- refactor: Update documentation and remove deprecated components
- feat: Implement agent execution API and delegate tool

## v0.1.9 — 2026-03-27

### What's changed

- docs: refresh release verification and agent scope matrix
- docs: refresh Release Smoke SHA, align ck-final Mission Control, missing/ hygiene

## v0.1.8 — 2026-03-25

### What's changed

- feat: benchmark quick presets, datalist hints, ignore session exports
- docs: support matrix, check.md classification, opencode archive note
- docs: include idea/missing/check.md FAQ in version control
- feat: P1 docs, mission graph UX, validate advisory metadata, release SHAs
- feat: update .gitignore and add opencode.md for project scope and requirements

## v0.1.7 — 2026-03-24

### What's changed

- feat: complete launch-ready OpenCode onboarding and benchmark flow

## v0.1.6 — 2026-03-24

### What's changed

- feat: add ops alignment runbook and Phoenix policy template
- feat: Introduce provider brokering with ephemeral project bindings and agent auto-bootstrap capabilities.

## v0.1.5 — 2026-03-19

### What's changed

- Reduce GitHub Actions Node 20 warnings
- Record green v0.1.4 release verification

## v0.1.4 — 2026-03-19

### What's changed

- Fix Homebrew release publish and add GitHub Packages

## v0.1.3 — 2026-03-19

### What's changed

- Record latest green release smoke SHA
- Fix workflow guard expressions
- Harden release workflow triggers
- Optimize release automation workflows

## v0.1.2 — 2026-03-19

### What's changed

- Fix Windows release archive path

## v0.1.1 — 2026-03-19

### What's changed

- Implement phase 3 platform and release closure
- Revise ControlKeel status audit to reflect closed MVP gaps and remove stale claims
- Expand audit log details and clarify Phase 2 implementation gaps in the ControlKeel status document
- Update release workflows for Node 24
- Treat Burrito as release runtime for migrations
- Cancel stale release workflow runs
- Run release migrations before starting endpoint
- Fix project binding path resolution on Windows
- Fix release smoke secret and diagnostics
- Run release CLI commands synchronously
- Skip Claude auto-attach in release smoke
- Resolve release smoke binary paths
- Halt standalone release commands synchronously
- Fix Burrito standalone argv handling
- Fix Burrito standalone CLI detection
- Finish agent integration surface and fix release smoke
- Fix Zig installer in release workflows
- Fix Burrito release packaging CI
- feat: add ControlKeel skills and benchmarks for governance and compliance
- feat: enhance mission and policy training features
- feat: add skills management and governance tools
- feat(api): update task completion logic to handle string task IDs
- feat: Cursor/Windsurf attach, episodic memory, benchmark scenarios, 12 domain packs, 28 Semgrep rules
- feat: agent router (Layer 3), proof bundles, audit log, HR/Legal/Marketing policy packs
- fix: downgrade Burrito 1.5.0→1.3.0, switch Zig to 0.14.0

## v0.1.0 — 2026-03-18

First public release.

### What's included

**Core governance engine**
- Three-tier scanner: FastPath (<5ms Elixir patterns + entropy analysis) → Semgrep SAST (29 rules across 9 languages) → Advisory LLM (optional 3rd tier)
- 12 policy packs, 62 rules total: Baseline Secrets, Baseline Injection, Cost, Software, Healthcare, Finance, Education, GDPR, HR, Legal, Marketing, Sales, Real Estate
- Per-session and rolling 24h budget enforcement with warn/block decisions
- MCP server (JSON-RPC 2.0 over stdio) with five tools: `ck_validate`, `ck_context`, `ck_budget`, `ck_finding`, `ck_route`
- HTTP proxy for OpenAI and Anthropic APIs — scans both request and response content

**Agent Router (Layer 3)**
- Automatic agent selection by task type, security tier, budget, and capability
- Supports 7 agents: claude-code, cursor, codex, bolt, replit, ollama, generic-cli
- Security tier enforcement: critical tasks route only to local agents (ollama, claude-code, cursor)
- Budget-aware: falls back to free local agents (ollama) when budget is low
- Exposed via `POST /api/v1/route-agent` and the `ck_route` MCP tool

**Web UI (5 LiveViews)**
- `/start` — Mission launch wizard with domain selection, agent picker, daily budget input
- `/missions/:id` — Real-time mission control with compliance score donut, task list, approve/reject findings
- `/findings` — Cross-session findings browser with severity/status/category filters
- `/policies` — Policy Studio showing active packs, rule counts, session budgets
- `/ship` — Install-to-first-finding funnel metrics

**REST API** (`/api/v1/`) — 13 endpoints
- Sessions CRUD, task creation + update + complete (gated), content validation
- Findings with actions (approve/reject/escalate), budget summary
- Proof bundle per task (`GET /proof/:task_id`)
- Audit log per session JSON + CSV (`GET /sessions/:id/audit-log`)
- Agent routing (`POST /route-agent`)

**Task completion gate**
- `Mission.complete_task/1` blocks marking a task "done" if any open or blocked findings exist
- Returns the list of unresolved findings so the caller can surface them

**Proof Bundle**
- Structured audit artifact per task: security findings, risk score, cost, deploy readiness, compliance attestations per domain pack

**Audit Log**
- Chronological invocations + findings for a session
- JSON (default) or CSV (`?format=csv`) for export into compliance tooling

**Episodic Memory**
- `ck_context` injects `past_patterns`: top recurring blocked rules from the last 10 sessions in the same domain pack
- SQL-based implementation (no pgvector required) using SQLite GROUP BY + ORDER BY

**CLI** (11 commands)
- `init`, `attach`, `status`, `findings`, `approve`, `watch`, `mcp`, `demo`, `version`, `help`
- `attach claude-code` — registers MCP server with Claude Code
- `attach cursor` — writes to `~/.config/Cursor/User/globalStorage/cursor.mcp.json`
- `attach windsurf` — writes to `~/.codeium/windsurf/mcp_config.json`
- Binary packaging via Burrito — no Erlang required on target machine

**Developer experience**
- `mix ck.demo` — benchmark: 10 real-world vibe coding failure scenarios (hardcoded keys, SQL injection, client-side auth bypass, unencrypted PHI, eval() RCE, open redirect, Supabase public bucket, PII to Segment, DEBUG=True in prod, pickle.loads deserialization RCE)
- `mix ck.watch` / `controlkeel watch` — live stream of findings and budget in the terminal
- 159 tests, 0 failures

### Semgrep rules (29 across 9 languages)

**Generic**: SQL injection, XSS sinks, `dangerouslySetInnerHTML`, inline scripts, hardcoded secrets, hardcoded JWT, `eval()`, `subprocess(shell=True)`, `os.system()`, `pickle.loads()`, `curl | bash`, `rm -rf`, prototype pollution, debug mode in prod, open redirect, hardcoded credentials

**Go**: sql.Query string format, hardcoded secret, exec injection

**Rust**: unwrap in handler, unsafe block, hardcoded secret

**Java**: SQL string concatenation, hardcoded secret, XXE

**Shell**: missing `set -e`

**HCL (Terraform)**: public S3 bucket

**Dockerfile**: running as root

**Ruby**: SQL string concatenation

**PHP**: `eval()` with user input

### Policy Packs (12 packs, 62 rules)

| Pack | Rules | Key concerns |
|------|-------|-------------|
| Baseline — Secrets | 5 | AWS keys, high-entropy tokens, hardcoded credentials |
| Baseline — Injection | 4 | SQL injection, eval/exec, unsafe HTML |
| Cost | 3 | Budget overrun, cost tracking |
| Software | 6 | Debug endpoints, CORS wildcard, console.log PII |
| Healthcare | 6 | HIPAA, PHI patterns, unencrypted patient data |
| Finance | 6 | PCI DSS, plaintext card numbers |
| Education | 6 | FERPA, student data exposure |
| GDPR | 6 | PII logging, unencrypted PII fields, third-party data sharing |
| HR | 6 | Employment PII, discriminatory criteria, salary data |
| Legal | 6 | Privileged content logging, e-discovery deletion |
| Marketing | 6 | Email unsubscribe, cookie consent, PII in analytics |
| Sales | 6 | CRM PII, revenue data logging, unsolicited email |
| Real Estate | 6 | Fair Housing criteria, SSN unencrypted, tenant data |
