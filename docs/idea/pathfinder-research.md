# Pathfinder Research: AI Agent Conductor for Vibe Coders

## Executive Summary

Build an **agent Conductor** — a meta-agent that sits above all coding agents (Claude Code, Codex, Cursor, OpenCode, Bolt, etc.) and provides planning, validation, governance, learning, and orchestration. The "engineering team in a box" for non-technical and technical users alike.

**Recommended Name: Bearings** (bearings.ai / bearings.dev) — check availability. Navigation metaphor: bearings tell you which direction to go. Also consider: **Railguard** (railguard.com / railguard.ai), or **Forepath** (forepath.com / forepath.ai).

---

## 1. Problem Space (Validated by Research)

### 1.1 User Pain Points (Real Users, Reddit, HN, Forums)

| Problem | Severity | Evidence |
|---------|----------|----------|
| **45% of AI-generated code contains OWASP Top 10 vulnerabilities** | Critical | Georgia Tech SSLab "Vibe Security Radar" tracking rising AI-linked CVEs (35 in March 2026 alone) |
| **The "Final 20%" problem** | High | Agents solve 80% fast, the last 20% (edge cases, architecture conformance, security) takes as long as manual coding |
| **Context collapse / memory loss** | High | Agents forget project conventions, lose state across sessions, cannot maintain architectural intent |
| **Security through obscurity** | Critical | Non-technical users commit secrets, API keys, exposed repos because they don't know what they don't know |
| **Cost unpredictability** | High | Users have no idea what their vibe-coded app costs to host, run, or scale — surprise AWS/GCP bills |
| **Compliance blindness** | High | No GDPR, HIPAA, SOC2 awareness — AI happily generates code that violates all of them |
| **"Architectural drift"** | High | AI modifications subtly erode design/security invariants over time without causing obvious errors |
| **PR incomprehensibility** | Medium | Humans can't review 2000-line AI-generated PRs — they just merge them |
| **Deployment ignorance** | High | Users don't understand Docker, CI/CD, hosting — the code runs locally but never ships |
| **No test culture** | High | Vibe coders don't write tests; AI-generated tests often just test that the code runs, not that it's correct |

### 1.2 Academic Research Findings

| Paper (2025-2026) | Key Finding |
|----------------------|-------------|
| **Security Degradation in Iterative AI Code Generation** (IEEE-ISTAS 2025) | Iterative AI refinement increases critical vulnerabilities — security gets *worse*, not better |
| **AI Code in the Wild: Security Risks and Ecosystem Shifts** (arXiv,2025) | AI-induced defects persist longer in human-AI edit chains where human review is shallow |
| **Assessing Quality and Security of AI-Generated Code** (arXiv 2025) | No correlation between functional performance (passing tests) and security quality |
| **Extracting Recurring Vulnerabilities from LLM-Generated Software** (arXiv 2026) | LLMs reproduce identical "insecure templates" across unrelated projects |
| **Vibe Security Radar** (Georgia Tech SSLab) | 35 CVEs in March 2026 linked to AI tools — this is a "lower bound" of the real problem |

### 1.3 Industry Trends (2026)

- **From Copilots to Autopilots**: Shift from AI-assisted to AI-autonomous workflows
- **From "impressive" to "accountable"**: Enterprise focus is on trust/reliability, not capability
- **Orchestration is the critical layer**: Multi-agent coordination > single-agent performance
- **Governance as a product category**: Agent observability/audit is now a standalone market segment

---

## 2. Competitive Landscape

### 2.1 Direct Competitors

| Company | What They Do | Funding | Gap |
|---------|-------------|---------|-----|
| **Sycamore Labs** | "Trusted agent OS" for enterprise agent fleets | $65M seed (Mar 2026) | Enterprise-only, not for vibe coders; no code generation guidance |
| **Virtue AI** | AI safety platform (red teaming, guardrails) | $30M (2025) | Security-only, doesn't guide code generation or plan projects |
| **CodeRabbit** | AI PR review | Bootstrapped | Review-only, no planning or agent orchestration |
| **Greptile** | Codebase-aware code review | Funded | Review-only, no agent routing or security enforcement |
| **Bifrost** | Runtime AI governance/enforcement | Funded | API-gateway level, doesn't touch code generation |
| **Credo AI** | AI governance/compliance platform | Funded | Enterprise compliance, not developer-facing |
| **Mem0** | Persistent memory for AI agents | Funded | Memory-only infrastructure, doesn't validate or govern |

### 2.2 Adjacent Players (Agent Makers)
| Tool | What It Does | Relevance |
|------|-------------|-----------|
| Claude Code | CLI coding agent | **The generator** — we sit above this |
| Cursor | IDE + AI agent | **The generator** — we sit above this |
| Codex CLI | Cloud coding agent | **The generator** — we sit above this |
| OpenCode | OSS coding agent | **The generator** — we sit above this |
| Bolt/Lovable/Replit | Vibe coding platforms | **The generators** — we sit above these |
| Windsurf/Kiro/Amp | AI-native IDEs | **The generators** — we sit above these |

### 2.3 The Gap (Why Now, Why Us)

**Nobody sits between the agent and the outcome.** The entire industry is:

| Layer | Products | What's Missing |
|-------|----------|---------------|
| Generation | Claude Code, Cursor, Codex, Bolt | Produces code fast |
| Review | CodeRabbit, Greptile, SonarQube | Check code after it's written |
| Governance | Bifrost, Credo AI, Sycamore | Enforce policies at API level |
| **ORCHESTRATION** | **Nobody** | **Plan → Route → Generate → Validate → Govern → Deploy → Learn** |

The missing layer is the **conductor** that:
1. Translates user intent into engineering specs
2. Plans the complete project journey (not just the next code change)
3. Routes work to the right agent at the right time
4. Validates everything across security, compliance, cost, architecture
5. Learns and improves over time
6. Handles everything non-code (deployment, cost, security, compliance)
7. Works across ALL agents and tools

---

## 3. Product: The Agent Conductor

### 3.1 Vision

> An autonomous companion that sits above all coding agents and handles everything the agents don't: planning, validation, governance, security, compliance, cost management, deployment guidance, and continuous learning. For non-technical users, it's the engineering team they never had. For technical users, it's the senior engineer/tech lead they always wished they had.

### 3.2 Product Name Recommendations (verify before registering)

| Name | Domain to Check | Metaphor | Why It Works |
|------|-----------------|----------|-------------|
| **Bearings** | bearings.ai, bearings.dev | Navigation bearings tell direction | Direction + guidance for agents |
| **Railguard** | railguard.com, railguard.ai | Guardrails for the rail (agent path) | Safety + guidance metaphor |
| **Forepath** | forepath.com, forepath.ai | The path ahead | Forward-looking + path planning |
| **Windrose** | windrose.com, windrose.ai | Navigation instrument that shows direction | Direction-finding for agents |
| **Trailcraft** | trailcraft.com, trailcraft.ai | Crafting trails | Trail-blazing + craftsmanship |

### 3.3 Core Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     USER INTENT (natural language)                    │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                        INTENT ENGINE                            │
│  • Natural language → structured engineering spec               │
│  • Domain-aware (healthcare/finance/e-commerce/...)             │
│  • Security requirements extraction                               │
│  • Compliance mapping (GDPR, HIPAA, SOC2, PCI-DSS)             │
│  • Cost/deployment architecture recommendations                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                       PLANNING ENGINE                           │
│  • Project decomposition into atomic tasks                      │
│  • Dependency graph generation                                  │
│  • Agent suitability scoring (which agent for which task)       │
│  • Risk assessment per task                                     │
│  • Cost estimation (tokens, hosting, API calls)                │
│  • Timeline generation                                          │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                    ORCHESTRATION ENGINE                          │
│  • Multi-agent task routing (Claude Code, Cursor, Codex, ...)   │
│  • Agent state management & context injection                  │
│  • Failure recovery & retry with alternate agent               │
│  • Progress tracking & checkpoint management                   │
│  • Human-in-the-loop decision points                          │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                     VALIDATION ENGINE                           │
│  • Security scanning (OWASP Top 10, CWE, secrets detection)     │
│  • Compliance verification (regulatory domain-specific)        │
│  • Architecture conformance (does code match the plan?)        │
│  • Test quality analysis (tests test correctness, not just run) │
│  • Cost tracking (tokens, API calls, hosting estimates)        │
│  • Performance profiling                                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                       GOVERNANCE LAYER                         │
│  • Budget controls (token spend limits, cost alerts)            │
│  • Security policies (no secrets in code, no public repos)     │
│  • Audit trail (every agent decision logged with rationale)    │
│  • Compliance checkpoints (auto-block on violations)           │
│  • Human approval gates (for high-risk operations)             │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                       LEARNING ENGINE                         │
│  • Persistent project memory (decisions, rationale, outcomes)   │
│  • Agent performance benchmarking (accuracy, speed, cost)      │
│  • Vulnerability pattern database (common AI mistakes)         │
│  • User preference adaptation                                   │
│  • Cross-project learning (patterns that transfer)             │
│  • Reinforcement from outcomes (deploy success/failure)        │
└───────────────────────────────────────────────────────────────────┘
```

### 3.4 Key Features (Ordered by Impact)

#### Tier 1: Safety Net (Ship Week 1)
1. **Secret Scanner** — Detect API keys, passwords, tokens before they leave the machine
2. **Security Gate** — Block commits containing OWASP Top 10 vulnerabilities
3. **Cost Guard** — Alert when token/hosting/API spend exceeds budget
4. **Repo Hygiene** — Enforce .gitignore, no public repos for private projects

#### Tier 2: Agent Orchestration (Ship Month 1)
5. **Agent Router** — Automatically pick best agent (Claude Code, Cursor, Codex, etc.) for each task
6. **Plan Mode** — Better than Claude Code's plan mode because it's multi-agent and cross-validates
7. **Context Persistence** — Never lose project state across sessions (solves the #1 complaint)
8. **Task Decomposition** — Break vague "build me an app" into structured, executable sub-tasks

#### Tier 3: Full Conductor (Ship Quarter 1)
9. **Compliance Engine** — Domain-aware (healthcare, finance, e-commerce) compliance checking
10. **Deployment Guide** — Step-by-step deployment for users who don't know what Docker is
11. **Learning Loop** — Reinforcement learning from outcomes (deploy success, test pass rates, security findings)
12. **Multi-tool Support** — Works with Claude Code, Cursor, Codex, OpenCode, Bolt, Replit, etc.

#### Tier 4: Autonomous Mode (Ship Quarter 2)
13. **Full Autopilot** — User describes intent, system handles everything from plan to deploy
14. **Continuous Monitoring** — Post-deploy security/performance monitoring
15. **Cross-Project Intelligence** — Learnings from one project improve all projects

### 3.5 Distribution

| Channel | Format | Priority |
|---------|--------|----------|
| **MCP Server** | stdio MCP protocol | P0 — any MCP-compatible agent can use it |
| **CLI** | Terminal-native | P0 — developers who live in the terminal |
| **VS Code Extension** | IDE-native | P1 — visual experience for IDE users |
| **Web Dashboard** | Browser-based | P2 — non-technical users, project tracking |
| **Cloud API** | REST API | P2 — enterprise integration |

### 3.6 How It Works with Every Agent

```
# MCP-compatible (Claude Code, Codex, OpenCode, Cursor, etc.)
User installs Conductor → Conductor attaches to agent via MCP → Conductor plans, validates, governs

# Non-MCP tools (Bolt, Lovable, Replit)
Conductor generates specs → user copies to tool → Conductor validates output

# Local LLM agents (Ollama, LM Studio)
Conductor plans → routes to local agent → validates against security baselines
```

---

## 4. Market Sizing

### 4.1 TAM (Total Addressable Market)

| Segment | Size (2026) | Source |
|---------|------------|--------|
| No-code/Low-code AI platforms | $4.88B - $8.6B | Multiple analyst reports |
| AI coding assistants (developer tools) | ~$15B | Market estimates |
| AI governance/compliance | ~$3B | Emerging market |
| **Total TAM** | **~$25B** | Combined |

### 4.2 SAM (Serviceable Addressable Market)
Our niche: **Agent orchestration + safety for non-technical/pro semi-technical AI users**

Estimated: **$2B - $4B** (subset of TAM that buys "conductor" layer)

### 4.3 SOM (Serviceable Obtainable Market)
Year 1 realistic target: **$500K - $2M ARR** (early adopters, individual users, small teams)
Year 3 target: **$5M - $15M ARR** (expanding to teams, enterprises)

### 4.4 Target Users

| Persona | Pain Level | Willingness to Pay | Size |
|---------|-----------|---------------------|------|
| **Vibe Coders** (non-technical) | EXTRE | $20-100/mo | Massive (growing fastest) |
| **Startup founders** | HIGH | $50-200/mo | Large (already using agents) |
| **Solo developers** | MEDIUM | $20-50/mo | Large |
| **Dev teams** | MEDIUM | $50-500/mo (team plans) | Large |
| **Enterprise** | VARIABLE | Custom pricing | Large but slower |

---

## 5. BLS Occupation Cross-Reference

Based on BLS data (2024-2034 projections), the product maps to occupation-specific AI capabilities:

| Occupation Category | Growth | How Our Product Helps | Example Occupations |
|---------------------|-------|---------------------|---------------------|
| **Computer & IT** (2.5M jobs) | +12% | Plan, validate, govern code for every IT task | Software devs, data scientists, security analysts |
| **Management** (2.5M jobs) | +8% | Agent-generated reports, compliance tracking | IT managers, project managers, construction managers |
| **Business & Financial** (2M jobs) | +6% | Automated analysis, compliance, audit trails | Financial analysts, compliance officers, accountants |
| **Healthcare** (8M jobs) | +13% | HIPAA-aware code generation, PHI handling | Health info technologists, medical services managers |
| **Architecture & Engineering** (1.5M jobs) | +6% | Spec-aware code, safety-critical validation | Engineers, engineering technicians |
| **Legal** (1M jobs) | +5% | Contract generation, compliance checking | Lawyers, paralegals, compliance officers |
| **Arts & Design** (300K jobs) | +2% | Design-to-code, brand-consistent output | Graphic designers, art directors |
| **Education** (3.5M jobs) | -2% | Content generation, assessment tools | Teachers, instructional coordinators |
| **Sales & Marketing** (2M jobs) | +4% | Landing page generation, CRM integration | Marketing managers, sales agents |
| **Production** (1.5M jobs) | -1% | Process automation, quality control systems | Industrial engineers, assemblers |

**Key insight**: The product isn't just for software — it's for ANY occupation where AI is being used to generate work product. A marketing manager using Bolt to build a landing pages needs the same governance as a developer building an API.

---

## 6. Go-to-Market Strategy

### 6.1 Phase 1: "Safety Net" (Week 1-4)
**Goal**: Become the default safety layer for existing agent users

| Tactic | Detail |
|---------|--------|
| **Product** | MCP server + CLI that wraps any agent with security/cost guards |
| **Channel** | Open source, npm/brew/pip install |
| **Message** | "You wouldn't drive without a seatbelt. Don't code with AI without [Name]." |
| **Hook** | Free tier: secret scanning + basic security gate |
| **Metrics** | Secrets caught, vulnerabilities blocked, cost saved |

### 6.2 Phase 2: "The Conductor" (Month 2-4)
**Goal**: Become the orchestration layer that routes between agents

| Tactic | Detail |
|---------|--------|
| **Product** | Plan mode + agent routing + context persistence |
| **Channel** | Integrations with Claude Code, Cursor, Codex marketplaces |
| **Message** | "Stop babysitting your AI. Let [Name] manage the agents." |
| **Hook** | Free planning, paid orchestration |
| **Metrics** | Tasks completed, agents orchestrated, time saved |

### 6.3 Phase 3: "Full Autopilot" (Month 5-8)
**Goal**: Become the autonomous engineering team for non-technical users

| Tactic | Detail |
|---------|--------|
| **Product** | Web dashboard + full autopilot mode + compliance engine |
| **Channel** | Product Hunt, HN, "vibe coding" communities, No-code directories |
| **Message** | "Describe your idea. [Name] builds it right." |
| **Hook** | Freemium: free planning, paid execution |
| **Metrics** | Projects shipped, compliance score, user retention |

### 6.4 Phase 4: "Enterprise" (Month 9-12)
**Goal**: Enterprise governance for agent fleets

| Tactic | Detail |
|---------|--------|
| **Product** | Cloud API + SSO + custom policies + audit dashboards |
| **Channel** | Enterprise sales, SOC2 compliance angle |
| **Message** | "Govern your AI workforce like you govern your human workforce." |
| **Hook** | Annual contracts, per-seat pricing |
| **Metrics** | ARR, enterprises onboarded, compliance audit hours |

---

## 7. Competitive Moat & Defensibility

### 7.1 Why This Is Hard to Copy

1. **Data Network Effects**: The learning engine gets smarter with every user. Vulnerability patterns from one project protect all users.
2. **Agent Integration Breadth**: Supporting 10+ agents creates switching costs. Each integration is weeks of work.
3. **Domain Expertise**: BLS occupation-specific compliance rules (HIPAA for healthcare, PCI for fintech) are expensive to build and maintain.
4. **Trust Barrier**: Security/compliance is a trust product. Once users trust us with their code, they don't switch.

### 7.2 Risks

| Risk | Mitigation |
|------|------------|
| **Agent makers add this natively** (Claude adds plan mode) | Our plan mode is multi-agent + cross-validated + learned. Single-agent plan modes are limited. |
| **Sycamore Labs dominates enterprise** | They're enterprise-only. We start with individual developers and expand up. |
| **Open source alternatives** | Open core orchestration, monetize learning data + compliance rules + enterprise features. |
| **Market timing** (vibe coding bubble bursts) | Even if vibe coding slows, existing developers still need agent orchestration. The problem persists. |

---

## 8. Technical Stack Recommendation

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Core Engine** | Elixir/OTP (Phoenix) | Already have this expertise. Excellent for concurrent agent orchestration. |
| **MCP Server** | Native stdio MCP | Already built in ControlKeel. Reuse the architecture. |
| **Security Scanner** | Tree-sitter + custom rules | Fast, local, no API dependency. OWASP + CWE coverage. |
| **Learning Store** | SQLite + embedded vector search | Local-first, works on smallest devices. |
| **Agent Routing** | Plugin architecture | Each agent is a "driver" that knows how to plan/route/validate for that agent. |
| **Web Dashboard** | Phoenix LiveView | Already have this expertise. Real-time agent status. |
| **Distribution** | Binary (Rust/Elixir release) | Single binary, no runtime dependencies. Works on ARM, x86, smallest VPS. |

---

## 9. Success Metrics & Validation

### 9.1 Proof Points (Before Building)
- [ ] Verify domain availability for top 3 name choices
- [ ] Run 5 user interviews with vibe coders (validate problem)
- [ ] Build secret scanner prototype (validate technical approach)
- [ ] Test MCP integration with 3 agents (validate orchestration)

### 9.2 MVP Metrics (Week 4)
- 1,000 GitHub stars (developer interest)
- 100 secret scans completed (value delivered)
- 10 beta users saving >$100 in avoided cloud costs

### 9.3 Product-Market Fit Indicators (Month 3)
- 70%+ weekly retention
- Users running conductor on >50% of their agent sessions
- NPS > 50 from beta users

### 9.4 Business Metrics (Month 6)
- $10K MRR
- 500+ active users
- 3+ agent integrations working reliably

---

## 10. Should We Build This? — Verdict

### YES. Here's why:

1. **The gap is real**: 45% vulnerability rate, rising AI-linked CVEs, massive "final 20%" problem. This isn't hypothetical.
2. **The timing is right**: Sycamore Labs just raised $65M for enterprise agent OS. The market is validating but they're enterprise-only. Individual developers and vibe coders are underserved.
3. **The competition is beatable**: Nobody is building the conductor layer for individual users. CodeRabbit reviews code. Sycamore governs enterprise fleets. We sit between the agent and the outcome.
4. **We have the expertise**: The ControlKeel codebase already has MCP server, agent integration, security scanning, benchmark infrastructure, and the Phoenix web stack. We're 60% of the way there.
5. **The market is massive**: 75% of new enterprise apps will use no-code by 2026. Every vibe coder is a potential user.
6. **It's not just about code**: Every occupation (BLS data shows 800+ categories) is being touched by AI. Our domain-aware approach scales beyond software.

### Critical Caveats:
- **Don't over-build**: Ship the safety net first (Tier 1), validate demand, then build up.
- **Don't compete on generation**: We're NOT an agent. We're the layer ABOVE agents.
- **Don't chase enterprise first**: Start with individual developers. Enterprise follows.
- **Don't ignore the name**: A great name with an available .ai domain matters for this market.

---

## 11. Recommended Next Steps

1. **Check domain availability** for Bearings, Railguard, and Forepath
2. **Pick a name** and register the domain
3. **Build the Secret Scanner** (1 week) — immediate value, validates technical approach
4. **Ship as MCP server** — works with every existing agent from day 1
5. **Get 10 beta users** from vibe coding communities (Reddit, Discord)
6. **Iterate based on feedback** before building the full conductor

This gives you a validated product, a clear technical path, and a go-to-market strategy that starts delivering value on day one.
