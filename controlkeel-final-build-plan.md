# ControlKeel — Final Product Plan

**Date**: March 18, 2026

---

## What We're Building

AI coding agents (Claude Code, Cursor, Codex, Bolt, Replit, Devin) write the code. They do not do the rest of software engineering. Everything else — security review, secrets management, compliance, cost governance, architecture decisions, deployment safety, PR scope, technical debt — falls on the user. Who has no idea.

ControlKeel is the **control plane that sits above all AI coding agents** and handles the rest. It does not generate code. It directs, constrains, validates, governs, and remembers — on behalf of anyone using AI to build anything.

The thesis: **agent generation is becoming a commodity. The winning layer is the system that makes agents usable, safe, and trustworthy for real delivery.**

---

## Name and Domain

**ControlKeel** — `controlkeel.com`

- Confirmed unregistered as of March 18, 2026 (RDAP 404)
- "Keel" = the structural spine of a ship. Invisible when things work. Everything collapses without it.
- "Control" = explicit governance, not autopilot magic
- Not tied to one model, one agent, or one use case
- Sounds serious. This is not a toy.

Fallback if taken: `agenthelm.ai`

**Tagline**: *The control plane that turns AI coding into production engineering.*

---

## The Problem (Backed by Data)

| Problem | Data |
|---------|------|
| AI-generated code is insecure | 45% of AI-generated code has OWASP Top-10 vulnerabilities |
| Secrets leak constantly | 28.65M hardcoded secrets on GitHub in 2025 — Claude Code-assisted code leaks at 2× baseline |
| Costs spiral out of control | $400M unbudgeted cloud spend in Fortune 500; 36% YoY cost growth |
| Projects fail | 73% of AI-built startups hit critical scaling failures by month 6 |
| Compliance is broken | 81% of teams deploying agents, only 14.4% have security approval |
| Regulation is live | Colorado AI Act enforcement June 30, 2026; EU AI Act active now |

The users who suffer most are non-technical people using vibe coding tools (Bolt, Loveable, Replit, v0) who cannot review what agents generate, do not understand hosting or secrets, and have no engineering team to catch mistakes.

But the problem is not limited to coders. The same control plane need exists for every occupation that AI agents will touch: healthcare workers automating billing, teachers generating curriculum, HR teams building screening tools, accountants automating reconciliation. Whenever AI agents are introduced, the layer above them is missing.

---

## What Already Exists (and Why It's Not Enough)

| Tool | What It Does | Why It Fails Vibe Coders |
|------|-------------|--------------------------|
| Factory.ai | Agent orchestration + PM | Enterprise-only, $500+/mo, requires senior engineers |
| Semgrep | Security scanning | Reactive (post-generation), requires security expertise |
| CloudZero | Cloud cost monitoring | Observability only, no enforcement |
| CodeRabbit | AI code review | PR-phase only, no orchestration |
| LangGraph / CrewAI | Agent frameworks | Require Python expertise to configure |
| Devin / SWE-agent | Code generation | Code generation, not governance |
| Agentik.md | Safety spec format | Markdown file, no enforcement, no UI |

The gap: **no product combines multi-agent routing + memory as governed infrastructure + policy-as-code + validation gates + proof artifacts + release readiness in something a non-technical person can actually use.**

ControlKeel occupies that gap before regulatory deadlines force enterprise buyers to act.

---

## Product Architecture: Six Layers

```
User Intent
     │
     ▼
┌─────────────────────────────────┐
│  1. INTENT COMPILER             │  Plain language → structured execution brief
│     (What are we building?)     │  Questions → scope → risk tier → constraints
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│  2. PATH GRAPH                  │  Tasks → dependencies → gates → cost estimate
│     (How do we build it?)       │  Small units, validation checkpoints, rollbacks
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│  3. AGENT ROUTER                │  Task → best agent → right environment
│     (Who builds each piece?)    │  Cost-aware, capability-aware, security-tier-aware
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│  4. POLICY ENGINE               │  Pre-execution firewall on every tool call
│     (What is allowed?)          │  Secrets, OWASP, network, filesystem, cost limits
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│  5. VERIFICATION ENGINE         │  Every task generates a proof bundle
│     (Did it work correctly?)    │  Tests, scans, diff summary, risk score, deploy check
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│  6. MEMORY SYSTEM               │  Typed, versioned, searchable, deletable
│     (What did we learn?)        │  Repo map, decisions, failures, benchmarks, costs
└─────────────────────────────────┘
```

This is not a prompt helper, a skills builder, a markdown generator, or a todo list. This is the full loop: **intent → plan → execute → validate → remember**. What an engineering team does, encoded as software.

---

## Layer Detail

### Layer 1: Intent Compiler

**Input**: User describes a goal in plain language.

**Process**:
1. Ask 4-5 high-signal clarifying questions (not a questionnaire — conversational, stops when enough context)
2. Infer: stack, data sensitivity, risk tier, compliance requirements, budget range, acceptance criteria
3. Flag ambiguities that would cause failures later
4. Produce a structured execution brief (JSON)

**Output — Execution Brief**:
```json
{
  "objective": "patient intake form for a small clinic",
  "users": "clinic staff, ~20 people",
  "data_sensitivity": "high — PHI",
  "risk_tier": "critical",
  "compliance": ["HIPAA", "HITECH"],
  "stack_recommendation": "Next.js + Postgres on Railway",
  "budget": "$30/month hosting",
  "acceptance_criteria": ["form submits without data loss", "data encrypted at rest", "audit log of access"],
  "open_questions": [],
  "estimated_tasks": 8,
  "estimated_cost_usd": 2.40
}
```

This is intent compilation, not prompt templating. The difference: it produces a machine-checkable artifact, not a better prompt.

---

### Layer 2: Path Graph

**Input**: Execution brief.

**Output**: A directed acyclic graph of tasks where each node has:
- Task name and description
- Assigned agent (or "router decides")
- Estimated token cost
- Validation gate (what proof is required before this node is "done")
- Rollback boundary (what can be undone if this fails)
- Confidence score (how certain ControlKeel is this task is well-scoped)

**Design principle**: Bias toward small changes and short feedback loops. A 500-line PR is a failure state, not a feature. The path graph enforces this structurally.

---

### Layer 3: Agent Router

**Decision criteria** (all weighted):
- Task type (repo-local changes → Claude Code; UI prototypes → Bolt/Replit; structured refactors → Codex)
- Security tier (PHI data → no cloud agents without explicit approval; local-only fallback)
- Cost budget (if remaining budget < estimated task cost → escalate to human)
- Model capability (SWE-bench scores by task category, updated from benchmarks)
- Latency requirements (interactive → fast model; batch → best model)
- Allowed tools (policy engine restricts what each agent can touch)

**Supported agent systems** (V1):
- Claude Code (via MCP server integration)
- OpenAI Codex (via CLI adapter)
- Cursor (via MCP server integration)
- Bolt / Loveable / Replit (via HTTP proxy — user's API key → ControlKeel proxy → provider)
- Local Ollama (via local proxy)
- Generic CLI adapter (for custom or future agents)

---

### Layer 4: Policy Engine

**This is the primary differentiator.**

Every tool call an agent makes — write file, run bash, fetch URL, call API, commit code — passes through the policy engine before execution. Nothing executes without passing.

**Policy architecture**:

Policies are stored as structured data files (YAML/JSON), not code. They can be updated for new regulations without a code deploy. Each policy has:
- `id` (unique, versioned)
- `severity` (critical / high / medium / low)
- `check` (pattern, AST rule, or entropy threshold)
- `action` (auto_fix / block / warn / escalate_to_human)
- `plain_message` (what the user sees — no technical jargon)

**Policy packs** (shipped in V1):
1. `baseline` — secrets detection (Shannon entropy + 400+ format-specific regexes), OWASP A01 injection, OWASP A03 XSS, path traversal, hardcoded credentials
2. `cost` — per-session budget, per-day budget, token counting per model, hard stops + warnings
3. `healthcare` — PHI pattern detection, HIPAA data handling rules, audit log requirements
4. `finance` — PCI-DSS card data patterns, SOX financial data markers
5. `education` — FERPA/COPPA pattern detection, age-appropriate content rules

**Three-tier detection pipeline** (performance vs. depth tradeoff):
```
Tool call arrives
     │
     ▼
FastPath (Elixir, <5ms)
  → Entropy analysis + 50 top regex patterns
  → Clear → pass immediately
  → Warning → log, continue
  → Hit → advance to Semgrep
     │
     ▼
Semgrep AST scan (async Port call, <2s)
  → Full structural analysis
  → No findings → pass
  → Findings → advance to LLM advisory
     │
     ▼
LLM Advisory (optional, <10s)
  → Plain-language explanation + suggested fix
  → User sees: "We blocked X because Y. Here's the fix."
```

---

### Layer 5: Verification Engine

Every completed task produces a **Proof Bundle** — a structured artifact that is the system-of-record for that task:

```json
{
  "task_id": "auth-001",
  "agent": "claude-code",
  "duration_ms": 48200,
  "cost_usd": 0.34,
  "test_outcomes": { "passed": 12, "failed": 0 },
  "security_findings": [],
  "diff_summary": { "files_changed": 3, "lines_added": 87, "lines_removed": 12 },
  "risk_score": 0.12,
  "deploy_ready": true,
  "rollback_instructions": "git revert abc123",
  "compliance_attestations": ["HIPAA_phi_check: passed", "secrets_scan: passed"]
}
```

Proof bundles are immutable once generated. They are the audit trail. They are exportable as PDF for regulatory compliance. They are the reason enterprise teams pay.

---

### Layer 6: Memory System

Memory is product infrastructure, not chat history.

**Three layers**:

1. **Working memory** (per-session, in-process) — current task state, active agent, budget consumed
2. **Episodic memory** (persistent, structured records) — every invocation, every finding, every proof bundle. Full replay possible. Schema:
   - `sessions` — start/end, domain, agent, total cost, outcome
   - `tasks` — session_id, description, agent, proof_bundle_id, duration, cost, reward_signal
   - `findings` — task_id, category, severity, rule_id, auto_resolved, plain_description
3. **Semantic memory** (vector embeddings) — project-level knowledge: what approaches worked, what compliance issues recurred, what the user's preferences are. RAG retrieval injects "what worked before" into agent context before each task.

**Memory rules** (from deep research):
- Scoped by project — not shared across workspaces by default
- Mutable only via auditable events (completed tasks, accepted decisions, incidents)
- Deletable — wrong memory causes persistent wrong behavior; users can purge
- No training on user data without explicit consent (critical for healthcare/legal users)

**Learning loop**:
- Feature vector: domain, agent, task type, compliance history score, budget ratio, error rate
- Reward: `delivery_quality - cost_penalty - user_friction_penalty`
- Policy: offline-trained MLP artifact (sklearn), loaded at runtime, scored in Elixir (no Python dependency at inference)
- Promotion gate: new policy artifacts only activate after passing held-out benchmark

---

## User Experience

The product must feel simpler than the systems it controls. This is the hardest design constraint.

### Onboarding (5 minutes)
1. **Who are you?** — 8 occupation tiles with icons (no compliance jargon; nurses pick "Healthcare", not "HIPAA")
2. **What are you building?** — Free text; ControlKeel asks 2-3 follow-up questions
3. **Which AI tool do you use?** — Pick from list; ControlKeel auto-configures integration
4. **Set your budget** — Slider from $0 to $100/day; plain-language cost examples ("That's about 3 full features per day")
5. **You're set.** — ControlKeel generates initial policy pack and starts monitoring

### Daily Driver (Proof Console)

**Five screens:**

**Mission Control** — Real-time view of what agents are doing
- Active run status (task name, agent, elapsed time, cost so far)
- Compliance score donut (green/amber/red)
- Recent findings feed ("blocked a hardcoded API key 4 minutes ago")
- Budget ticker

**Path Graph** — Visual task DAG
- Nodes: todo / in-progress / done / blocked
- Each node: task name, agent, estimated cost, evidence collected
- Click any node to see proof bundle

**Proof Browser** — All evidence for all tasks
- Filter by: security findings / test failures / compliance gaps / cost overruns
- One-click: approve (next task starts) / reject (agent re-runs with finding as context)

**Policy Studio** — Governance configuration
- Active policy packs listed plainly ("Healthcare: HIPAA compliance active")
- Edit budget limits, domain settings
- Advanced: view/edit policy rules (power user only; defaults work for everyone)

**Audit Log** — Immutable record
- Every tool call, every policy decision, every outcome
- Export to PDF for compliance reporting

### Tone of All User-Facing Text
- No security jargon ("We blocked a potential API key from your code" not "Entropy threshold exceeded for secret pattern AKIA")
- No technical stack details in warnings
- Always tell users what was fixed automatically vs. what needs their decision
- Never block without explaining why in plain language

---

## Interfaces

### Control Tower Web App (Primary)

React single-page app. Server-rendered on Phoenix for SEO and first load. LiveView for real-time updates (findings feed, cost ticker, run status). Deployed at `app.controlkeel.com`.

**Why web app first, not CLI**: The target novice audience does not live in a terminal. The web app is the product. The CLI is for power users.

### CLI (`controlkeel` or `ck`)

```bash
ck init                        # Set up ControlKeel for this project (generates policy pack, configures integrations)
ck attach claude-code          # Register MCP server in ~/.claude/settings.json automatically
ck status                      # Show compliance score, cost, active findings
ck findings --severity high    # List findings
ck approve <id>                # Approve a human-escalated finding
ck watch                       # Real-time stream of agent activity
```

Distributed as a single binary (Bakeware). `brew install controlkeel/tap/ck` or `curl | sh`. No Docker, no Python, no npm. Works on 8GB RAM. This is the install path for non-technical users.

### MCP Server (IDE/Agent Integration)

ControlKeel runs as an MCP server that Claude Code, Cursor, and Windsurf register via their config files. Every tool call routes through ControlKeel before execution.

MCP tools exposed:
- `ck_validate` — validate a proposed action before execution
- `ck_context` — fetch compliance-aware context for current task
- `ck_finding` — report a finding and get a ruling
- `ck_budget` — check remaining budget before an expensive operation

`ck init` writes the MCP registration automatically. User does not touch JSON config.

### HTTP Proxy (Web Agent Integration)

For Bolt, Loveable, Replit, v0, AI Studio, and any API-based tool: users point their API key destination to `https://proxy.controlkeel.com/openai` instead of `https://api.openai.com`. ControlKeel intercepts every request/response, runs the policy engine, and passes through or blocks.

Zero changes required to the target tool.

### REST API (Enterprise / Automation)

```
POST   /api/v1/sessions            Start a governed agent session
GET    /api/v1/sessions/:id        Session status + findings
POST   /api/v1/sessions/:id/tasks  Add a task to a session
POST   /api/v1/validate            Synchronous compliance check (<100ms)
GET    /api/v1/findings            List findings
POST   /api/v1/findings/:id/action Approve / reject / escalate
GET    /api/v1/budget              Current spend vs limits
GET    /api/v1/proof/:task_id      Get proof bundle for a task
```

---

## Occupation Domain Registry

Users pick who they are. ControlKeel handles the rest.

```
"I'm a nurse / doctor / admin"  → healthcare   → HIPAA, HITECH, PHI patterns, clinical templates
"I'm a teacher / trainer"       → education    → FERPA, COPPA, age-appropriate content rules
"I'm an accountant / analyst"   → finance      → SOX, PCI-DSS, financial data markers
"I'm a founder / developer"     → software     → OWASP full 10, secrets, deploy readiness
"I'm in HR / recruiting"        → hr           → EEOC, PII, employment law templates
"I'm a lawyer / paralegal"      → legal        → attorney-client privilege, data retention, eDiscovery
"I'm in marketing / content"    → marketing    → brand safety, copyright, data consent
"I'm in sales / ops"            → sales        → CRM data handling, quota accuracy, data privacy
```

826 BLS occupations map to 23 domain categories. Same engine runs unchanged. Only the policy pack and context preamble differ. This is the expansion path: **build the control plane once, swap domain packs for each market**.

Each domain pack is:
- Compliance rule set (which policy IDs are active)
- Context preamble injected into agent system prompts
- Output validation schema
- Cost budget defaults
- Human escalation triggers
- Acceptance criteria templates

---

## Technical Stack

| Component | Technology | Why |
|-----------|-----------|-----|
| Backend language | Elixir/OTP + Phoenix 1.8 | BEAM actor model is architecturally correct for 24/7 autonomous agent governance; existing patterns in agentic-nasa are directly portable |
| Frontend | React + Tailwind | AgentHelm prototype has proven UX flow and design system |
| Real-time UI | Phoenix LiveView | Already proven for streaming dashboards; no WebSocket boilerplate |
| CLI distribution | Bakeware single binary | Zero install friction; non-technical users; ~15MB |
| Desktop (Phase 3) | Tauri (Rust + React) | Cross-platform native app; OS-level hooks for non-MCP agents |
| DB (local) | SQLite + Ecto | Zero ops; single file; runs air-gapped |
| DB (cloud) | Postgres 16 + pgvector | Vector search without separate service |
| LLM client | Provider-agnostic (Ollama + OpenAI-compatible) | Works local and cloud; rate limiting + caching built in |
| Security scanning | Elixir FastPath + Semgrep port + TruffleHog port | Graduated depth: fast (inline) → thorough (async) |
| Secrets detection | Pure Elixir (entropy analysis + 400+ regexes) | Inline, <5ms, no subprocess |
| RL inference | Pure Elixir JSON policy artifact | No Python at inference; offline training pipeline |
| Compliance rules | YAML/JSON data files | Regulatory updates without code deploys |
| Vector search | pgvector (cloud) / in-memory (local) | No separate service required |
| Message queue (cloud) | NATS JetStream | Lightweight, Elixir-native, multi-region |
| MCP protocol | Phoenix GenServer over stdio | Native Claude Code / Cursor / Windsurf support |
| HTTP proxy | Plug pipeline (Elixir) | Intercepts web agent API calls |

**What to pull from existing projects** (not rebuild):

From agentic-nasa:
- `lib/agentic_nasa/llm/client.ex` → `ControlKeel.LLM.Client` (provider-agnostic LLM HTTP client with rate limiting and caching)
- `lib/agentic_nasa/llm/rate_limiter.ex` → `ControlKeel.LLM.RateLimiter`
- `lib/agentic_nasa/agents/policy_service.ex` → `ControlKeel.GovernancePolicy` (MLP artifact loading + pure Elixir scoring)
- `lib/agentic_nasa/agents/agent.ex` → `ControlKeel.InvocationEngine` (experiment lifecycle pattern)
- `lib/agentic_nasa/agents/swarm_coordinator.ex` → `ControlKeel.AgentRouter`
- `lib/agentic_nasa/persistence/persistence.ex` → `ControlKeel.Persistence`
- `lib/agentic_nasa_web/live/dashboard_live.ex` → `ControlKeel.Web.MissionControlLive`

From AgentHelm prototype:
- Industry selector component + compliance framework mapping
- Agent selector component + file format mapping
- Interview question flow
- SpecDisplay tab layout
- ValidationDisplay score card
- Full design system (`#c4f042`, dark background, DM Serif + Outfit fonts)

From OS Ghost:
- Credential detection patterns (20+ formats, already written)
- BeforeToolCall / AfterToolCall hook architecture (for Phase 3 Tauri layer)
- Hybrid memory structure (SQLite + FTS5 + vector)
- Prometheus + OpenTelemetry observability setup

---

## Distribution Tiers

| Tier | Target | Infrastructure | Pricing |
|------|--------|---------------|---------|
| **Free** | Solo founders, freelancers, non-technical individuals | Single binary, SQLite, Ollama support, air-gapped capable | $0 |
| **Team** ($20/seat/mo) | Startups, small professional teams | Managed cloud, Postgres + pgvector, shared policies, team approvals | Per seat |
| **Enterprise** ($50K–$500K ACV) | Fortune 500, healthcare systems, financial institutions, law firms | Self-hosted Docker/K8s, NATS, SAML SSO, air-gapped, audit export | Volume |

Expansion note: The regulatory tailwind (Colorado AI Act June 2026, EU AI Act) creates immediate enterprise demand. A CISO who must demonstrate AI governance before June 30 will pay. But do not chase enterprise on day one — the product-led free tier is the acquisition channel.

---

## MVP: 6-Week Build Plan

**Definition of done**: A non-technical user can install ControlKeel, attach it to Claude Code, run a session, and see ≥1 security or cost finding described in plain English — in under 10 minutes from first install.

### Week 1 — Foundation

- New Elixir/Phoenix app `controlkeel`
- Port from agentic-nasa: `LLM.Client`, `RateLimiter`, `Persistence`
- Core Ecto schemas: `workspaces`, `sessions`, `tasks`, `findings`
- SQLite in dev; Postgres config ready
- MCP server GenServer skeleton (JSON-RPC over stdio)
- `ck_validate` MCP tool — stub that returns "approved" (wire logic in Week 2)

### Week 2 — Security Scanner

- FastPath scanner (pure Elixir): secrets detection (Shannon entropy + top-50 credential regexes) + OWASP A01 injection + OWASP A03 XSS
- Plain-language finding message map (no LLM call for common findings — static lookup, sub-millisecond)
- Semgrep Port integration: subprocess call, JSON output parsing, mapping to `Finding` struct
- `ck_validate` MCP tool wired to FastPath scanner

### Week 3 — Claude Code Integration + HTTP Proxy

- All 4 MCP tools functional; end-to-end tested with real Claude Code sessions
- `ck init` CLI: creates `controlkeel/` config dir, writes MCP registration to `~/.claude/settings.json` automatically, no user JSON editing
- HTTP proxy Plug pipeline: intercepts completions from Bolt/Loveable/Replit, runs FastPath scanner
- Budget tracking: token counting + provider cost lookup table; per-session and per-day hard stops

### Week 4 — Intent Compiler + Web UI

- Intent compiler: 4-question interview flow → structured execution brief (LLM-backed, server-side)
- Port AgentHelm prototype UI to proper React app backed by Phoenix API (no API keys in browser)
- Onboarding: occupation selector, agent selector, interview, spec display
- Mission Control LiveView (adapt agentic-nasa DashboardLive): active runs, finding feed, cost ticker

### Week 5 — Auto-Fix + Domain Packs

- Auto-fix for top-5 findings: env var replacement for hardcoded secrets, SQL parameterization hints, innerHTML → textContent alternatives
- 3 domain packs: `software` (OWASP + secrets + cost), `healthcare` (HIPAA + PHI), `education` (FERPA + COPPA)
- Findings Browser LiveView (adapt agentic-nasa DiscoveriesLive): filterable, approve/reject per finding
- Path graph: basic linear task list with status per node (full DAG in Phase 2)

### Week 6 — Ship

- Bakeware single binary: tested on clean macOS (Apple Silicon), Ubuntu 22.04, Windows 11
- Getting-started guide: 5 minutes written + 3-minute screen recording
- Soft launch: 5 non-technical beta users; target is 10 minutes install-to-first-finding; watch sessions
- Instrumentation: time-to-first-finding, finding rate per session, where users drop off

**What to NOT build in MVP:**
- RL training pipeline (ship heuristic policy first)
- Vector semantic memory (episodic is sufficient)
- More than 3 domain packs
- Enterprise SSO or multi-user workspace
- Cursor integration (Claude Code MCP first, then Cursor)
- Full OWASP coverage (A01 + A03 + secrets = ~80% of real incidents)
- Desktop app (web + CLI first)

---

## Post-MVP Roadmap

### Phase 2 — Validation and Memory (Months 2-3)

- Structured memory: typed records per task, searchable across sessions
- pgvector semantic memory: RAG retrieval injects relevant past outcomes into agent context
- Full proof bundle per task: test outcomes, scan results, diff summary, risk score, deploy readiness
- Task resume: pause and restart long-running tasks with full context preserved
- RL offline training pipeline (Python/sklearn): policy artifact promoted to Elixir runtime
- Benchmark dashboard: PR size trend, security finding rate, cost per shipped task, deploy success rate
- 5 more domain packs
- Cursor + Windsurf MCP integration

### Phase 3 — Team and Platform (Months 4-5)

- Shared workspaces: team-level policies and approvals
- Org-level spend controls and budgets
- Audit log PDF export (EU AI Act / Colorado AI Act compliance artifact)
- Enterprise HTTP proxy with team policy sets
- NATS JetStream for multi-node cloud deployments
- REST API + webhooks for CI/CD integration
- Tauri desktop app: OS-level hooks for non-MCP agents, screen-aware overlay

### Phase 4 — Domain Expansion (Month 6+)

Same engine, new domain packs. Each pack is:
- One compliance rule set (JSON)
- One context preamble
- One acceptance criteria schema
- One set of escalation triggers

Target domains: legal, HR, real estate, media production, construction admin, insurance underwriting, pharma R&D, government operations. Per BLS occupational landscape: 826 occupations across 23 major groups, each a market.

---

## The Benchmark (Marketing Flywheel)

This is the most important thing to ship before any paid acquisition spend.

Run the same 10 real-world "vibe coding failure" scenarios — based on documented incidents (Enrichlead client-side auth bypass, Moltbook Supabase misconfiguration, Loveable 16-vulnerability data leak, SaaStr autonomous agent DROP DATABASE, Builder.ai) — through:

1. Claude Code alone
2. Claude Code + ControlKeel

Measure:
- Secrets detected before commit
- OWASP violations caught pre-execution
- Cost overruns prevented
- Time added to workflow (target: <15% overhead)

**Target**: ControlKeel catches ≥80% of issues Claude Code alone produces.

Publish this. Make it reproducible. Invite third parties to verify it. This benchmark becomes the acquisition engine: every security-conscious developer who sees it tries the free tier.

---

## Why Users Will Pay

ControlKeel must show numbers, not claims. Dashboard metrics from day one:

| Metric | User-facing label |
|--------|------------------|
| Findings blocked this session | "We blocked 3 security issues today" |
| Estimated cost prevented (vs no budget limits) | "$140 saved vs uncapped" |
| Secrets caught before commit | "0 credentials leaked this month" |
| Tasks completed with proof bundle | "12/12 tasks have full evidence" |
| PR size (trend over time) | "Average PR size: 87 lines (down 60%)" |

These numbers compound over time. A user who has been running ControlKeel for 3 months has a proof record that is genuinely valuable: an audit trail, a benchmark history, and a learning model that has adapted to their project.

That accumulation is the retention moat.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Too abstract for novice users | High | High | Test onboarding weekly with non-technical users; iterate until 10-minute goal is met |
| Coding agents absorb governance features | Medium | High | Cross-agent positioning protects against any single agent expanding; build fast |
| Cloud vendors build governance layers | Medium | Medium | Focus on developer-local tier first; enterprise relationships built on compliance proof |
| Colorado/EU AI Act requirements change | Low | Low | Compliance rules as data files — no code deploy required |
| Trying to cover too many domains too early | High | Medium | 3 domains in MVP, then earn expansion through user demand signals |
| Overbuilding orchestration before proving core need | High | High | The MVP is a single-agent intercept, not a multi-agent orchestration platform |

The biggest risk is building the full vision before proving the wedge. The wedge is: **"ControlKeel blocks secrets before Claude Code commits them."** That single feature, working perfectly, is enough to get the first 100 users and the first benchmark.

---

## Success Criteria

### Phase 0 (Day 1 demo)
A single 3-minute screen recording showing: Claude Code writes a hardcoded API key → ControlKeel intercepts and replaces it with an env var reference → user sees plain-language explanation.

### MVP (6 weeks)
- 10-minute install-to-first-finding for a non-technical user with no assistance
- ≥1 finding per Claude Code session of typical duration
- Binary installs cleanly on macOS, Ubuntu, Windows

### Month 3
- 100 active workspaces
- Published benchmark: ControlKeel vs. Claude Code alone on 10 real failure scenarios
- ≥80% finding catch rate on benchmark scenarios
- <15% workflow overhead vs. no governance

### Month 6
- 1,000 active workspaces
- 5+ domain packs (software, healthcare, education, finance, HR)
- First enterprise customer (LOI or paid contract)
- RL policy demonstrably improving over heuristic baseline on user cohort
