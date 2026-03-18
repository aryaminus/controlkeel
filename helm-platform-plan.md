# HELM — AI Agent Governance Platform
## Full Product Plan

---

## Context

AI coding agents (Claude Code, Cursor, Codex, Bolt, Replit, Devin) have reached the point where a non-technical person can describe something and watch code appear. But the agents only handle one slice of what a real engineering team does: writing code. Everything else — security review, compliance, secrets management, cost governance, deployment safety, technical debt, architecture decisions — falls completely on the user. Who has no idea.

The result, backed by 2025–2026 data:
- **45% of AI-generated code** contains OWASP Top-10 vulnerabilities
- **28.65M hardcoded secrets** leaked to GitHub in 2025 (34% YoY rise) — Claude Code-assisted code leaks secrets at **2× the baseline rate**
- **$400M** in unbudgeted cloud spend from Fortune 500 running AI workloads
- **73% of AI-built startups** hit critical scaling failures by month 6
- **Only 14.4%** of agentic AI deployments have security approval — 81% are past planning but blocked by the compliance gap
- Colorado AI Act enforcement begins **June 30, 2026**; EU AI Act is already in effect

Current tools are siloed. Semgrep scans code reactively. CloudZero monitors costs but doesn't control them. CodeRabbit reviews PRs but doesn't orchestrate agents. Factory.ai and LangGraph orchestrate but require senior engineers to configure. Nothing exists that is:
1. Cross-platform (works with every agent tool)
2. Non-technical user-first (nurses, teachers, HR managers, accountants)
3. Compliance-first and proactive, not reactive
4. Applicable beyond software — to all 826 BLS occupations

**HELM** is that layer. It sits between users and their AI agents. It doesn't write code — it governs, validates, routes, remembers, and improves. It's the technical co-founder everyone needs and nobody has.

---

## Product Vision

> "You bring the idea. HELM handles everything an engineering team does around it."

**Core positioning**: HELM is the control plane for AI agents — for everyone. Not another AI that writes code. The layer above all AI tools that makes what they produce safe, compliant, cost-controlled, and production-ready.

**The autopilot metaphor**: Users set their destination and budget. HELM pilots the agents, intercepts unsafe actions, surfaces only genuine decisions to humans, learns from every run, and improves continuously. Set it and forget it.

---

## Name & Domain

**Product Name: HELM**

- **Primary domain**: `helm.ai`
- Metaphor: "at the helm" = governing and steering, not rowing
- Universal (not coding-specific), short, memorable
- Alternatives if unavailable: `steer.ai`, `lodestar.ai`, `waypoint.ai`

**Action required**: Verify domain availability at Namecheap/Cloudflare before finalizing.

---

## Market Opportunity

| Metric | Value |
|--------|-------|
| Autonomous AI agent market (2026) | $8.5B |
| Same market (2030) | $35–45B |
| AI orchestration market (2030) | $30B |
| AI code tools market (2026) | $10B |
| Non-technical agent builders (current) | 30% of teams |
| Enterprise apps with embedded agents by end 2026 | 40% (Gartner) |
| Teams past planning, blocked by compliance | 81% |
| Teams with security approval | 14.4% |

**Regulatory tailwind**: Colorado SB 24-205 enforcement **June 30, 2026**. EU AI Act active now. NIST AI Agent Standards Initiative launched February 2026. Companies must demonstrate compliance tooling — urgency is non-negotiable and creates immediate enterprise demand.

**Investment climate**: Boards making AI oversight a standing agenda item. Zenity, WitnessAI raised in 2025–26. CrewAI: $18M Series A, $3.2M revenue. The governance layer is the next funding wave.

---

## Competitive Landscape

| Tool | What It Does | The Gap |
|------|-------------|---------|
| Factory.ai | Agent orchestration + PM | Enterprise-only, $500+/mo, requires senior engineers |
| Semgrep | Security scanning | Reactive (post-gen), requires security expertise to configure |
| CloudZero | Cloud cost monitoring | Observability only, no enforcement |
| CodeRabbit | AI code review | PR-phase only, no orchestration |
| LangGraph/CrewAI | Agent frameworks | Require Python expertise |
| Devin/Claude Code/Cursor | Code generation | Siloed per-platform, no cross-tool governance |
| Agentik.md / NIST | Safety spec formats | Markdown/docs only, no enforcement, no UI |

**The unclaimed quadrant**: Non-technical users + cross-platform governance + compliance-first. Nobody owns it. HELM's moat is occupying this position before regulatory deadlines force enterprise buyers to act.

---

## Core Capabilities (The 7 Pillars)

### 1. Harness
Wraps every agent interaction in a controlled sandbox. Agents cannot write files, call APIs, or commit code without passing through HELM. Resource quotas enforced. Execution time-boxed. Every action is recorded.

### 2. Context Builder
Before every agent run: assembles task-relevant memory via RAG, injects domain-specific compliance constraints as system prompt additions, scrubs PII. The agent runs smarter and safer without the user doing anything.

### 3. Orchestration
Routes tasks to the best available agent (cost, capability, context-aware). Coordinates multi-agent runs. Handles retries, partial failures, rollbacks. **The Pathfinder function**: users describe a goal — HELM decomposes it into tasks, estimates cost, and presents a plain-language plan for approval before any agents run.

### 4. Invocation Engine
Actually executes the agents. Tracks every invocation as a structured experiment (pre-metrics, action, post-metrics, reward signal) feeding the learning system.

### 5. Validation Gate
Blocking checkpoint between agent output and any persistent action. Nothing exits the sandbox without passing. Response: approve / approve-with-warnings / auto-fix / block / escalate-to-human.

### 6. Compliance Engine

**SecurityScanner**: OWASP Top-10 detection via three-tier pipeline:
- FastPath (pure Elixir, <5ms) — regex patterns for injection, XSS, hardcoded creds, path traversal
- Semgrep AST analysis (async Port call, <2s) — full structural analysis
- LLM advisory (optional, <10s) — explanation + suggested fix for complex cases

**SecretDetector**: Shannon entropy analysis + 400+ regex patterns for specific credential formats (AWS keys, GitHub tokens, JWTs, DB connection strings). Auto-replaces detected secrets with env var references.

**CostGuard**: Real-time token/spend tracking per provider. Warns at 75% and 90% of budget. Hard stops at 100%.

**RegulatoryFilter**: Jurisdiction-aware rule sets — HIPAA, FERPA, COPPA, GDPR, SOX, PCI-DSS, Colorado AI Act, EU AI Act. Rules stored as JSON/YAML data files, not code — update without recompilation.

Non-technical users see only: "We found a security issue and fixed it" or "We need your input — [plain English description]."

### 7. Memory & Learning System

**Working memory**: In-process GenServer state, per-session, ephemeral.

**Episodic memory**: Structured records of every invocation, finding, and outcome persisted to SQLite/Postgres. Full replay possible. Same pattern as `ExperimentRecord`/`Discovery` in agentic-nasa.

**Semantic memory**: Vector embeddings of project outcomes and domain knowledge stored in pgvector. RAG retrieval automatically injects "what worked before" into agent context — agents naturally avoid previously-flagged patterns.

**RL Policy**: Offline-trained MLP artifact (Python/sklearn) loaded at runtime and scored in pure Elixir — no Python dependency at inference. Same pattern as `PolicyService` in agentic-nasa. Learns which compliance checks produce best outcomes with least user friction. New policy artifacts activate only after passing a held-out benchmark gate.

---

## Occupation Domain Registry

Users never select a compliance framework. They answer one question: **"What best describes your work?"**

```
"I'm a nurse"            → :healthcare       → HIPAA + PHI patterns + clinical workflow templates
"I'm a teacher"          → :education        → FERPA + COPPA + lesson plan templates
"I'm an accountant"      → :finance          → SOX + PCI-DSS + reconciliation templates
"I'm building a startup" → :general_software → OWASP + secrets + cost + deploy templates
"I'm in HR"              → :human_resources  → EEOC + PII + onboarding workflow templates
"I'm a lawyer"           → :legal            → attorney conduct rules + confidentiality + document templates
```

826 BLS occupations mapped to 23 domain categories. Same engine, different configuration. The Pathfinder decomposes goals domain-appropriately — "automate my medical billing workflow" produces a HIPAA-safe plan; "build a customer support bot" produces different guardrails.

Each domain template contains:
- Compliance rules (active rule IDs)
- Forbidden agent actions (e.g., `:internet_access_without_approval` for healthcare)
- Cost budget defaults
- Context preamble injected into agent system prompts
- Output validation schemas
- Human escalation triggers (e.g., `:phi_detected`, `:clinical_decision_boundary`)

---

## Agent Integration Protocol

### Universal Three-Phase Pattern

**Pre-flight**: HELM assembles context, checks budget, loads domain template, injects compliance constraints.
**Intercept**: HELM monitors agent outputs via the appropriate mechanism for the tool.
**Validate**: Gate runs, outcome recorded as experiment, reward signal updated.

### Integration by Tool

| Tool | Mechanism |
|------|-----------|
| Claude Code | MCP server registered in `~/.claude/settings.json` — all tool calls pass through HELM |
| Cursor | Same MCP registration |
| Bolt / Loveable / Replit | HTTP proxy: user's API key → `helm.ai/proxy/openai` → provider |
| Ollama (local LLMs) | Local proxy at `localhost:14340` wrapping Ollama's 11434 |
| LangGraph / CrewAI / AutoGen / ADK | Drop-in OpenAI-compatible API endpoint |
| Unknown/other tools | File system watcher for post-hoc compliance scan (fallback mode) |

The HTTP proxy pattern enables HELM to work with **any** API-based AI tool with zero changes to that tool. This is the key to universal coverage.

---

## Interfaces

### CLI (`helm`)

```bash
helm init --domain healthcare          # Initialize project with domain + compliance profile
helm attach --tool claude-code         # Auto-register MCP server in Claude Code config
helm run "build patient intake form" --budget 10.00  # Governed agent run
helm status                            # Compliance score + cost summary
helm findings --severity high          # List high-severity findings
helm approve <finding-id>              # Unblock human-escalated action
helm server start                      # Start local daemon + web UI on localhost:4000
helm watch                             # Real-time agent activity stream
```

**Distribution**: Single binary via Bakeware. `brew install helm-ai/tap/helm` or `curl | sh`. No Docker, no Python, no npm required. ~15–20 MB executable. Runs on 8 GB RAM.

### Web Dashboard (Phoenix LiveView — 5 screens)

1. **Mission Control** — active runs, compliance score donut, cost ticker, live finding feed
2. **Findings Browser** — filterable/paginated findings, one-click approve/reject/auto-fix
3. **Domain Configurator** — plain-language occupation selector, budget limits, compliance profile (zero technical jargon)
4. **Policy Studio** — RL policy history, A/B comparison, benchmark results, promotion status
5. **Audit Log** — full replay of every invocation, immutable append-only, PDF export for compliance reporting

### MCP Server (IDE integration)

Exposes 5 tools to Claude Code / Cursor:
- `helm_validate` — validate a proposed action before execution
- `helm_context` — fetch compliance-aware context for current task
- `helm_finding` — report a finding and get a ruling (approve/fix/block)
- `helm_budget` — check remaining budget before an expensive operation
- `helm_approve` — escalate a blocked action to human

### REST API

```
POST   /api/v1/runs              — start a governed agent run
GET    /api/v1/runs/:id          — run status + findings
POST   /api/v1/runs/:id/approve  — approve a blocked finding
GET    /api/v1/findings          — list findings (filterable)
POST   /api/v1/validate          — synchronous compliance check (returns in <100ms)
GET    /api/v1/budget            — current spend vs. limits
POST   /api/v1/context           — get assembled context for a task
GET    /api/v1/domains           — list occupation domain templates
```

---

## Distribution Tiers

| Tier | Target User | Infrastructure | Pricing Model |
|------|-------------|---------------|---------------|
| **Edge / Local** | Solo founders, freelancers, non-technical individuals | Single binary, SQLite, Ollama support — runs air-gapped | Free |
| **Team / SaaS** | Startups, small practices, school districts | Managed cloud, Postgres + pgvector, multi-user | Per-seat ($15–30/mo) |
| **Enterprise / Self-hosted** | Fortune 500, healthcare systems, financial institutions | Docker Compose or K8s Helm chart, NATS, Qdrant, SAML SSO | Volume licensing ($50K–500K ACV) |

**The "smallest device" strategy**: Elixir/BEAM idle memory usage is <50 MB. A Raspberry Pi 5 or a $6/mo VPS can serve a 5-person team. The single binary is the key unlock for non-technical adoption — zero install friction.

---

## Technical Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language/runtime | Elixir/OTP + Phoenix 1.8 | Existing expertise; BEAM actor model is perfect for agent orchestration |
| Frontend | Phoenix LiveView 1.1+ | Proven in agentic-nasa; real-time streaming without WebSocket boilerplate |
| DB (local) | SQLite + Ecto | Zero ops, zero deps, same as existing project |
| DB (cloud) | Postgres 16 + pgvector | Adds vector search without a separate service |
| LLM client | Adapted from `agentic_nasa/llm/client.ex` | Provider-agnostic, Ollama + OpenAI, rate limiting, caching — battle-tested |
| RL inference | Pure Elixir JSON artifact | No Python at inference — proven in `policy_service.ex` |
| Security scanning | Elixir FastPath + Semgrep port | Graduated depth: fast inline scan then async thorough scan |
| Secrets detection | Pure Elixir (entropy + regex) | Inline, <5ms, no subprocess |
| MCP server | Phoenix GenServer over stdio | Native Claude Code / Cursor / Windsurf support |
| Distribution | Bakeware single binary | Zero friction for non-technical users |
| Compliance rules | JSON/YAML data files | Regulatory updates without code changes |
| Vector search | pgvector (cloud) / in-memory (local) | No separate service in MVP |
| Message queue (cloud) | NATS JetStream | Lightweight, Elixir-native, multi-region |
| HTTP client | Req (already in agentic-nasa) | Already proven, used for all provider calls |

---

## Code Reuse from agentic-nasa

Port these files directly — they are battle-tested and directly applicable:

| Source | HELM Equivalent | Why Reusable |
|--------|-----------------|-------------|
| `lib/agentic_nasa/llm/client.ex` | `Helm.LLM.Client` | Provider-agnostic HTTP + rate limiting + caching |
| `lib/agentic_nasa/llm/rate_limiter.ex` | `Helm.LLM.RateLimiter` | Direct reuse |
| `lib/agentic_nasa/llm/reasoning_cache.ex` | `Helm.LLM.ReasoningCache` | Direct reuse |
| `lib/agentic_nasa/agents/policy_service.ex` | `Helm.CompliancePolicy` | MLP artifact load + pure Elixir scoring |
| `lib/agentic_nasa/agents/agent.ex` | `Helm.InvocationEngine` | Experiment lifecycle + LLM advisory integration |
| `lib/agentic_nasa/agents/swarm_coordinator.ex` | `Helm.Orchestrator` | Multi-agent coordination |
| `lib/agentic_nasa/persistence/persistence.ex` | `Helm.Persistence` | Ecto query patterns, upsert-on-conflict |
| `lib/agentic_nasa_web/live/dashboard_live.ex` | `Helm.Web.MissionControlLive` | PubSub + LiveView stream feed |
| `lib/agentic_nasa_web/live/discoveries_live.ex` | `Helm.Web.FindingsLive` | Paginated feed with actions |

---

## MVP Build Plan — 6 Weeks

**Success criteria**: Non-technical user installs HELM, attaches to Claude Code, runs a session, sees ≥1 security or cost finding described in plain language. **Under 10 minutes from first install.**

### Week 1 — Foundation
- New `helm` Phoenix app bootstrapped from scratch
- Port `LLM.Client`, `RateLimiter`, `Persistence` from agentic-nasa
- Core Ecto schemas: `sessions`, `invocation_records`, `findings`
- SQLite in dev; Postgres config ready for cloud
- MCP server GenServer skeleton (JSON-RPC over stdio, `helm_validate` stub functional)

### Week 2 — Security Scanner
- FastPath scanner in pure Elixir: secrets detection (entropy + 50 most common regex patterns) + OWASP A01 (injection) + A03 (XSS)
- Plain-language finding message lookup (static map — no LLM call for common findings, sub-millisecond response)
- Semgrep port integration: Port worker, JSON output parsing, mapping to HELM `Finding` structs

### Week 3 — Claude Code Integration
- All 5 MCP tools functional; end-to-end test with real Claude Code sessions
- `helm init` CLI: creates project config, registers MCP server in `~/.claude/settings.json` automatically
- `helm attach` CLI: attaches to existing project
- HTTP proxy Plug pipeline for Bolt/Loveable/Replit (intercepts completions, runs FastPath scanner)

### Week 4 — Web Dashboard
- Mission Control LiveView (adapt `DashboardLive` — same PubSub subscription pattern, same stream)
- Findings Browser LiveView (adapt `DiscoveriesLive` — filterable, paginated, approve/reject actions)
- Domain Configurator: 3 domains (`general_software`, `healthcare`, `education`) with plain-language occupation selector tiles (icons, no jargon)

### Week 5 — Cost Guard + Auto-Fix
- Token counting + provider cost lookup table (price per token per model, all major providers)
- Per-session and per-day budget enforcement with hard stops at 100%, warnings at 75%/90%
- Auto-fix for top-5 findings: env var replacement for hardcoded secrets, SQL parameterization hints, `innerHTML` → `textContent` alternatives

### Week 6 — Ship
- Bakeware single binary; tested on clean macOS (Apple Silicon) + Ubuntu 22.04
- 5-minute getting-started guide; screen recording walkthrough
- Soft launch with 5 non-technical beta users; time install-to-first-finding; watch sessions
- Instrument everything: time-to-first-finding, drop-off points, finding rate per session

### What NOT to Build in MVP
- RL training pipeline — ship heuristic policy (same fallback as agentic-nasa's `TabulaRasa`) first
- Vector semantic memory — episodic memory sufficient for MVP
- More than 3 occupation domains
- Enterprise SSO or multi-user workspace
- Cursor as primary integration (Claude Code MCP first)
- Full OWASP coverage — A01 + A03 + secrets covers ~80% of real-world findings

---

## Post-MVP Roadmap

| Phase | Timeline | Key Deliverables |
|-------|----------|-----------------|
| **Phase 2** | Months 2–3 | RL offline training pipeline, pgvector semantic memory, 5 more occupation domains, full OWASP via Semgrep |
| **Phase 3** | Months 4–5 | 20+ domains, enterprise HTTP proxy with team policies, NATS multi-node, REST API + webhooks, audit log PDF export |
| **Phase 4** | Months 6+ | Pathfinder autonomous goal decomposition, fine-tuned local compliance LLM (runs on device), K8s Helm chart, enterprise SAML SSO |

---

## Verification & Benchmarks

### MVP Acceptance Tests
1. `helm init` completes in <60 seconds on a clean machine with no prior setup
2. Claude Code session containing a hardcoded API key → HELM detects and alerts within the same session
3. Budget set to $1.00 → agent run that would exceed it is stopped with a plain-language message
4. Non-technical user (no engineering background, recruited externally) completes onboarding without assistance
5. Findings Browser shows at least one finding after a 5-minute Claude Code session

### Technical Tests (ExUnit)
- FastPath scanner: 50+ known-bad code snippets, each triggers the correct finding category
- MCP protocol: all 5 tools respond correctly to JSON-RPC 2.0 requests; tested with Claude Code directly
- HTTP proxy: clean requests pass unmodified; requests containing secrets are blocked/modified
- Cost tracking: token counts within 2% of provider's reported usage
- SQLite → Postgres migration: zero data loss, all queries produce identical results

### End-to-End Benchmark (The Core Marketing Proof)
Run the same 10 "vibe coding" prompts (drawn from documented real-world failures — Enrichlead, Moltbook, Loveable incidents) through:
1. Claude Code alone
2. Claude Code + HELM

Measure: secrets detected before commit, OWASP violations caught, cost overruns prevented, total time added to workflow.

**Target**: HELM catches ≥80% of known issues that Claude Code alone produces. Workflow overhead <15% of session time.

This benchmark becomes the primary marketing asset: concrete, reproducible, third-party verifiable.

---

## Key Decisions Summary

| Decision | Choice | Why |
|----------|--------|-----|
| What HELM does | Governs agents, doesn't generate code | Differentiates from every competitor; defends the "above all tools" position |
| First integration | Claude Code via MCP | Cleanest intercept mechanism; largest power-user base |
| Distribution | Single binary via Bakeware | Non-technical user requirement; zero install friction |
| Compliance rules | Data-driven JSON/YAML | Update for new regulations without code deploys |
| User onboarding | Occupation selector, not framework selector | Nurses don't know what HIPAA rule 164.312(b) is; they know they're nurses |
| Stack | Elixir/OTP | Existing expertise + BEAM is architecturally correct for 24/7 autonomous agent governance |
| RL in MVP | No — heuristic first | Ship fast; RL adds marginal value in week 1; optimize after you have data |
| Market entry | Developer-facing (Claude Code users) | Easy to reach, high pain, willing to pay; expand to non-technical after proof |
