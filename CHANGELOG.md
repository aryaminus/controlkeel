# Changelog

## v0.2.43 — 2026-04-24

### What's changed

- fix(benchmarks): track repo benchmark subjects for ci
- feat(governance): expand diagnostic findings coverage
- feat(benchmarks): add multi-host comparison workflow

## v0.2.42 — 2026-04-22

### What's changed

- Enhance promotion integrity checks and decision prompts across modules

## v0.2.41 — 2026-04-21

### What's changed

- feat: add diagnostics for daemon role fields in skill metadata and enhance parser validation
- feat: add frontmatter hygiene diagnostics for third-party skills in parser

## v0.2.40 — 2026-04-21

### What's changed

- feat: add interoperability guidelines for external optimizers in benchmarks documentation
- feat: enhance non-server endpoint configuration and update review timeout handling

## v0.2.39 — 2026-04-21

### What's changed

- fix: update documentation for Codex integration and user checkpoints

## v0.2.38 — 2026-04-21

### What's changed

- ci: parallelize release smoke linux and windows builds

## v0.2.37 — 2026-04-20

### What's changed

- fix: soften codex stop hook blocked-findings warning

## v0.2.36 — 2026-04-20

### What's changed

- docs: clarify lean harness guidance for host integrations

## v0.2.35 — 2026-04-20

### What's changed

- test: add comprehensive tests for t3code integration, governance, and runtime conformance
- feat(governance): add canonical event bridge, turn lifecycle, thread state, and budget telemetry
- feat(governance): add approval adapter, idempotency ledger, and remote session claims
- feat(governance): add runtime policy profiles, orchestration event namespace, and wire into recommendations
- feat(integration): promote t3code from alias to first-class attach client
- feat(runtime): add capabilities callback to Runtime behaviour and implement across all runtimes
- feat(docs): enhance documentation on agent integrations, control-plane architecture, and skill package distribution; clarify workflow phases and supply chain considerations

## v0.2.34 — 2026-04-19

### What's changed

- feat(governance): improve code-mode routing and plan-review fallback
- feat(docs): enhance documentation on progressive discovery, human wake-up surfaces, and enterprise control-plane posture feat(core): improve project root resolution logic and enhance advisory status handling test: add tests for CK_PROJECT_ROOT usage in advisory status resolution

## v0.2.33 — 2026-04-19

### What's changed

- fix(mcp): harden launcher fallback and add troubleshooting guidance

## v0.2.32 — 2026-04-19

### What's changed

- feat(cli): add 'attach doctor' command for post-attach verification and health checks
- feat(cli): add status option to watch command and improve error handling for connection failures
- fix(docs): update target from 'codex' to 'opencode' in AGENTS.md and refine setup instructions in README.md
- docs: add one-line setup instructions for ControlKeel in README

## v0.2.31 — 2026-04-18

### What's changed

- feat(runtime): add codex app-server support and sqlite busy retries
- fix(cli): accept positional target for skills export/install subcommands
- fix(test): loosen session_id error message assertion in api_controller_test
- fix: guard jq calls in user-prompt-submit hook against non-JSON context output
- feat: close all Claude integration gaps — write hooks, governance injection, full tool coverage
- feat: add claude-sdk target and SDK integration guidance for Agent SDK
- feat: Add SubagentStart/PostToolUseFailure/ConfigChange/PermissionDenied hooks and fix plugin agent
- feat: Enhance Claude Code integration with full lifecycle hooks, marketplace, and skill metadata
- feat: Enhance Codex CLI integration with lifecycle hooks and configuration updates

## v0.2.30 — 2026-04-18

### What's changed

- chore(registry): align server metadata with 0.2.29 publish

## v0.2.29 — 2026-04-18

### What's changed

- chore(registry): prepare npm package metadata for MCP publish

## v0.2.28 — 2026-04-18

### What's changed

- fix(governance): keep escalated findings human-gated
- Merge branch 'fix/ck-review-store-split'
- fix(mcp): broaden review fallback variants for split runtime contexts
- Merge branch 'fix/ck-review-store-split'
- feat(harness): surface explicit harness principles
- fix(opencode): restore linked CLI execution and tighten governance skill guardrails

## v0.2.27 — 2026-04-18

### What's changed

- feat(update): surface release checks across host agents

## v0.2.26 — 2026-04-17

### What's changed

- docs(cli): add help entries for agent routing and task lifecycle commands
- fix(governance): harden review workflows and runtime host defaults

## v0.2.25 — 2026-04-17

### What's changed

- fix(mcp): prevent review tool endpoint crashes

## v0.2.24 — 2026-04-17

### What's changed

- fix(opencode): mirror legacy config for MCP attach
- fix(opencode): stabilize governed plan-review transport and MCP startup

## v0.2.23 — 2026-04-16

### What's changed

- chore(cursor): align plugin manifest version with app release

## v0.2.22 — 2026-04-16

### What's changed

- fix(governance): auto-resolve matching findings on allow rulings

## v0.2.21 — 2026-04-16

### What's changed

- fix(opencode): harden submit-plan JSON handling in release flows
- docs(opencode): document MCP enabled verification and local attach fallback
- fix(opencode): write enabled MCP entries for local server

## v0.2.20 — 2026-04-16

### What's changed

- fix(mcp): bootstrap installs stdio launcher for CK source; track priv template
- fix(opencode): make local MCP launcher respond under persistent stdio
- fix(cli): force standalone logger output to stderr so `--json` responses stay machine-readable in release flows
- fix(opencode): harden submit-plan JSON parsing and error handling when CLI output includes non-JSON lines

## v0.2.19 — 2026-04-16

### What's changed

- fix(opencode): align native integration with OpenCode surfaces
- feat(hooks): update permission decision for PreToolUse event in ck_copilot_hook.sh

## v0.2.18 — 2026-04-16

### What's changed

- refactor(hooks): remove unused SubagentStop and Stop hooks; enhance logging in ck_copilot_hook.sh
- feat(governance): implement ControlKeel hooks and update version to 0.2.17

## v0.2.17 — 2026-04-16

### What's changed

- Internal maintenance release.

## v0.2.16 — 2026-04-15

### What's changed

- fix(claude): make `attach claude-code` idempotent when MCP server already exists
- fix(mcp): ensure stdio server startup before MCP CLI handoff and improve launcher stdio reliability
- chore(qa): add full Copilot parity script with bounded MCP/attach checks for deterministic audit runs

## v0.2.15 — 2026-04-15

### What's changed

- feat(update): add release-aware upgrade flow

## v0.2.14 — 2026-04-15

### What's changed

- feat(cli): add context and validate commands

## v0.2.13 — 2026-04-15

### What's changed

- fix(mcp): filter mix stdout in bin/controlkeel-mcp for stdio JSON

## v0.2.12 — 2026-04-15

### What's changed

- fix(mcp): stderr logging in CK_MCP_MODE; align Cursor integration docs
- fix(mcp): stdio newline-delimited JSON-RPC per MCP spec
- fix(mcp): handle JSON-RPC 2.0 batches (Cursor handshake)
- fix(mcp): avoid Registry scans on tools/list and resources/list in stdio
- chore(mcp): stderr boot timing, app.start --no-compile, SQLite busy_timeout
- fix(mcp): defer Repo/bus boot so Cursor can finish initialize
- fix(mcp): source-tree launcher uses mix ck.mcp, not release bin
- fix(mcp): dogfood source tree prefers local release/mix over PATH controlkeel
- fix(mcp): prefer local mix release binary over mix ck.mcp when present
- fix(mcp): use IO.binwrite for stdio and binary io opts in reader
- fix(mcp): flush stdout after each framed JSON-RPC response
- fix(mcp): skip Phoenix CodeReloader when CK_MCP_MODE for faster Mix boot
- fix(mcp): defer release migrations until after MCP children start
- fix(mcp): supervise stdio server before Repo under CK_MCP_MODE
- fix(mcp): prefer repo bin launcher for Cursor in ControlKeel source tree
- fix(mcp): keep stdio stdout JSON-only for Cursor handshake

## v0.2.11 — 2026-04-15

### What's changed

- fix(mcp): skip attached-agent sync during stdio MCP startup

## v0.2.10 — 2026-04-15

### What's changed

- fix(install): scrub AGENTS.md before ControlKeel block; portable project hint

## v0.2.9 — 2026-04-15

### What's changed

- fix(mcp): Cursor stdio — workspaceFolder launcher path and CK_PROJECT_ROOT scan

## v0.2.8 — 2026-04-15

### What's changed

- chore: align Cursor plugin manifest version with app (0.2.7)
- Fix Cursor MCP stuck on Loading tools (quiet stdout for stdio MCP)

## v0.2.7 — 2026-04-15

### What's changed

- cli: use pipe separator in status and watch output

## v0.2.6 — 2026-04-15

### What's changed

- Fix Cursor bundle: priv skill precedence, portable MCP paths
- feat: enhance task verification and assurance features
- feat: add retrieval strategy configuration and support for multiple strategies in ControlKeel
- chore: update .gitignore, enhance AGENTS.md, and improve logger configuration in runtime.exs

## v0.2.5 — 2026-04-13

### What's changed

- Add Cursor plugin, fix MCP server encoding, and expand Cursor integration surface

## v0.2.4 — 2026-04-12

### What's changed

- Improve Codex install surfaces and governance docs

## v0.2.3 — 2026-04-11

### What's changed

- Expose Cloudflare runtime export in CLI
- Add skill quality diagnostics
- Add harness policy to intent boundary
- Fix init and attach project-root parsing

## v0.2.2 — 2026-04-11

### What's changed

- Expose skills as MCP resources
- Add provider trust-boundary reporting
- Add split-aware eval profiles to benchmarks
- Quiet CLI smoke output in test runs
- Add governed decomposition summaries to mission state

## v0.2.1 — 2026-04-10

### What's changed

- Add Letta Code native attach support

## v0.2.0 — 2026-04-10

### What's changed

- Add Executor runtime export support
- Add virtual bash runtime export
- Align runtime export docs and API metadata

## v0.1.43 — 2026-04-09

### What's changed

- Add JSON output mode for core CLI reads

## v0.1.42 — 2026-04-09

### What's changed

- Improve CLI proofs progress and benchmark ergonomics

## v0.1.41 — 2026-04-09

### What's changed

- Make CLI status and findings more agent ergonomic

## v0.1.40 — 2026-04-08

### What's changed

- Add derived task augmentation context

## v0.1.39 — 2026-04-08

### What's changed

- Add autonomy and improvement loop summaries

## v0.1.38 — 2026-04-08

### What's changed

- Surface security case triage summaries

## v0.1.37 — 2026-04-07

### What's changed

- Tighten security workflow proof gating

## v0.1.36 — 2026-04-07

### What's changed

- Add defensive security workflow to ControlKeel
- Add detailed ControlKeel architecture walkthrough
- Add plain-English ControlKeel explainer

## v0.1.35 — 2026-04-07

### What's changed

- Harden agent-facing validation and context resolution

## v0.1.34 — 2026-04-07

### What's changed

- Align web project-root context with CLI

## v0.1.33 — 2026-04-07

### What's changed

- Harden Codex dogfooding surfaces

## v0.1.32 — 2026-04-07

### What's changed

- Use canonical docs for wrapper aliases
- Add public host drift audit
- Make runtime recommendations availability-aware

## v0.1.31 — 2026-04-07

### What's changed

- Make typed storage explicit in execution posture

## v0.1.30 — 2026-04-07

### What's changed

- Add execution posture guidance to intent context

## v0.1.29 — 2026-04-07

### What's changed

- Ignore generated editor companion artifacts
- Harden OpenCode submit_plan execution

## v0.1.28 — 2026-04-07

### What's changed

- Improve OpenCode plan review integration
- Add .copilot/skills to project skill directories

## v0.1.27 — 2026-04-07

### What's changed

- Ignore local attach artifacts in repo
- Fix Codex self-hosting attach and install paths

## v0.1.26 — 2026-04-07

### What's changed

- Align Codex integration with native skills

## v0.1.25 — 2026-04-07

### What's changed

- Handle virtual workspace grep without ripgrep
- Clarify hosted MCP scope guidance
- Apply formatting after precommit
- Refresh integrations and export Droid plugin bundles
- Add governed MCP control-plane surfaces

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
