# Gap Analysis: ControlKeel vs Pathfinder Research

## Scorecard

| Dimension | Pathfinder Plan | CK Status | Coverage |
|-----------|----------------|-----------|----------|
| 1. Intent Engine / Planning | Intent → structured spec, task decomposition, dependency graph | **BUILT**: `Intent.compile/2`, `ExecutionBrief`, `Mission.Planner.build/1`, `TaskGraph` with DAG edges | 90% |
| 2. Agent Orchestration | Route work to best agent, failure recovery, retry alternate | **BUILT**: `AgentRouter` (67 agents), `AgentExecution` (4 modes), `ExecutionSandbox` (3 adapters) | 85% |
| 3. Security / Validation | OWASP Top 10, CWE, secrets, entropy, 3-layer scanning | **BUILT**: 3-layer scanner (regex/entropy → Semgrep → LLM advisory), PII detection | 80% |
| 4. Compliance | HIPAA, GDPR, SOC2, PCI-DSS domain packs | **BUILT**: 18 policy packs covering all major compliance frameworks | 90% |
| 5. Governance | Budget controls, audit trails, human approval gates | **BUILT**: Budget tracking, proof bundles, audit exports (JSON/CSV/PDF), service accounts, webhooks, GitHub governance scaffolding | 85% |
| 6. Learning / Memory | Persistent memory, RL from outcomes, cross-project learning | **PARTIAL**: Memory store (Pgvector/SQLite), benchmark engine, policy training. Missing: RL loop, cross-project transfer | 55% |
| 7. Cost Management | Token spend, API costs, hosting estimates, budget alerts | **PARTIAL**: Per-token pricing for 8 models, session budgets, budget policy rules. Missing: hosting cost estimation, real-time spend alerts | 60% |
| 8. Deployment Guidance | Docker, CI/CD, hosting help for non-technical users | **MINIMAL**: Release readiness gate, GitHub Actions scaffolding. Missing: deployment guidance for non-technical users | 20% |
| 9. Multi-agent Support | Works with all agents (CLI, IDE, cloud, local) | **BUILT**: 30 attachable integrations, 67 routed agents, MCP protocol, A2A protocol | 95% |
| 10. Distribution | MCP, CLI, web, VS Code, cloud API | **BUILT**: MCP server, CLI (60+ commands), LiveView web, REST API (40+ endpoints), A2A, proxy, skills, brew, npm | 90% |

**Overall: ~75% built. 25% gap.**

---

## What's Fully Built (No Gap)

### Intent Engine / Planning ✅
- `ControlKeel.Intent.compile/2` — compiles user intent into structured `ExecutionBrief` via LLM
- `ExecutionBrief` — embedded schema with project name, idea, objective, users, occupation, domain pack, risk tier, compliance, acceptance criteria, estimated tasks
- `Mission.Planner.build/1` — builds workspaces, sessions, tasks, findings, and task edges (DAG) from a brief
- `TaskGraph` — dependency graph with `build_edges/1` and `ready_task_ids/2`
- Industry profiles with compliance mapping (healthcare → HIPAA, finance → PCI-DSS, etc.)
- Multi-provider fallback (Anthropic → OpenAI → OpenRouter → Ollama)

### Agent Orchestration ✅
- `AgentRouter` with 67 agents across 9 categories, scoring on SWE-bench, security tier, budget, capability
- `AgentExecution` with 4 execution modes (direct, handoff, runtime, inbound_only)
- `ExecutionSandbox` with 3 adapters (local, Docker, E2B)
- `ACPRegistry` syncs with Agent Client Protocol registry
- `AgentIntegration` catalog with 30+ integrations and full metadata

### Security / Validation ✅
- 3-layer scanner pipeline:
  - Layer 1: Regex patterns + Shannon entropy detection + budget rules
  - Layer 2: Semgrep AST-based static analysis
  - Layer 3: LLM advisory (logic flaws, access control, unsafe data flows)
- `PIIDetector` for PII detection
- Finding lifecycle: allow → warn → block → escalate_to_human
- Categories: security, privacy, compliance, dependencies, cost

### Compliance ✅
- 18 policy packs: baseline, cost, gdpr, healthcare, finance, ecommerce, education, government, legal, hr, insurance, manufacturing, logistics, nonprofit, realestate, sales, marketing, software
- JSON-based rules with regex/entropy/budget matchers
- Domain pack loading at scan time based on session context
- Industry-to-compliance mapping in `Intent.Domains` and `Mission.Planner`

### Multi-agent Support ✅
- 30 attachable integrations (claude-code, cursor, codex, opencode, windsurf, kiro, amp, gemini-cli, continue, aider, cline, roo-code, goose, etc.)
- 67 routed agents across 9 categories
- MCP protocol (8 tools: validate, context, finding, budget, route, delegate, skill_list, skill_load)
- A2A protocol with agent cards and OAuth2
- OpenAI/Anthropic/Gemini-compatible proxy

### Distribution ✅
- MCP server (stdio + hosted)
- CLI (60+ commands)
- LiveView web UI (onboarding, mission control, ship, findings, proofs, benchmarks, policy studio, skills)
- REST API (40+ endpoints with API key auth)
- Homebrew, npm, shell installer, PowerShell installer
- Skills system (11 built-in skills)
- 16 Mix tasks
- Event bus (NATS or local)

---

## What's Partially Built (Needs Work)

### Learning / Memory ⚠️ 55%

**What exists:**
- `Memory.Store` — dual backend (Pgvector vector search / SQLite FTS)
- `Memory.Embeddings` — embedding generation via OpenAI
- Benchmark engine with 5 suites, multi-subject comparison, domain-pack filtering
- Policy training pipeline (train → promote → archive lifecycle)
- Self-improvement loop: benchmarks → policy training → router scoring → re-benchmark

**What's missing:**
1. **Reinforcement learning from outcomes** — No RL agent that learns from deploy success/failure. Policy training uses scripted scores, not reward signals from real outcomes.
2. **Cross-project learning** — Memory is per-project. No mechanism to transfer learnings (e.g., "this vulnerability pattern appeared in 3 other healthcare projects") between projects.
3. **Vulnerability pattern database** — No centralized database of "common AI mistakes" that grows over time from all users' findings.
4. **User preference adaptation** — No learning of user-specific patterns (e.g., "this user prefers React over Vue, prefers Tailwind over CSS modules").
5. **Agent performance benchmarking over time** — Benchmarks run on-demand but no continuous tracking of agent performance degradation or improvement.

### Cost Management ⚠️ 60%

**What exists:**
- `Budget.Pricing` — per-token cost estimation for 8 models (Anthropic + OpenAI)
- Session budget caps (`budget_cents`, `daily_budget_cents`, `spent_cents`)
- Budget policy rules (warn at 75%, block at 95%)
- `ck_budget` MCP tool for agents
- Token tracking in invocations

**What's missing:**
1. **Hosting cost estimation** — No estimation of what the vibe-coded app costs to run (AWS/GCP/Vercel/Render). A user builds an app and has no idea what it costs to deploy.
2. **Real-time spend alerts** — No push notifications when spending spikes or approaches limits.
3. **Cost optimization suggestions** — No "you're spending $X/month on this API, consider caching or switching models" recommendations.
4. **Multi-model pricing coverage** — Only 8 models covered. Missing: Gemini, DeepSeek, Groq, Together, Cohere, local model electricity costs, etc.
5. **Agent cost comparison** — No "Claude Code would cost $X for this task, Codex would cost $Y" pre-flight estimates.

### Governance ⚠️ 85%

**What exists:**
- Budget tracking, proof bundles, audit exports (JSON/CSV/PDF)
- Service accounts with token auth
- Webhooks with HMAC signing and retry
- GitHub Actions governance scaffolding
- Release readiness gate
- PR/patch review

**What's missing:**
1. **Real-time agent monitoring dashboard** — No live view of what agents are doing right now (which tool calls, what files being modified). The LiveView shows findings but not live agent activity.
2. **Circuit breaker for rogue agents** — No automatic shutdown when an agent's behavior deviates from baseline (e.g., sudden high-frequency API calls, unusual file access patterns).
3. **Policy violation auto-block** — Governance reviews are post-hoc. No pre-commit hooks that automatically block violations before they enter the repo.

---

## What's Mostly Missing (Major Gaps)

### Deployment Guidance ❌ 20%

**What exists:**
- Release readiness gate (checks proofs, findings, smoke evidence)
- GitHub Actions workflow scaffolding

**What's completely missing:**
1. **Docker/containerization guidance** — No help generating Dockerfile, docker-compose.yml for the vibe-coded app
2. **Hosting platform recommendations** — No "your app is a Phoenix app, here's how to deploy to Fly.io/Render/Railway/AWS"
3. **CI/CD pipeline generation** — No automatic GitHub Actions / GitLab CI config for the user's project
4. **Domain/DNS setup** — No guidance on domain registration, DNS configuration
5. **Environment variable management** — No help setting up .env files, secret management for production
6. **Database migration guidance** — No help running migrations in production
7. **SSL/HTTPS setup** — No guidance on certificate management
8. **Scaling considerations** — No "your app will hit X concurrent users, here's what to provision"
9. **Monitoring/alerting setup** — No help setting up application monitoring

**This is the biggest gap.** Non-technical users can build apps but can't ship them. This is the "last mile" problem.

### Non-Technical User Onboarding ❌ 30%

**What exists:**
- `OnboardingLive` — guided setup wizard
- `Intent.compile/2` — natural language to structured spec
- `Mission.Planner` — generates tasks from specs

**What's missing:**
1. **Visual project builder** — No drag-and-drop or visual interface for describing what you want to build
2. **Plain English explanations** — Findings use technical language. No "here's what this means in plain English" mode for non-technical users.
3. **One-click deploy** — No integration with deployment platforms for push-button shipping
4. **Guided tutorials** — No interactive tutorials teaching users basic concepts (what's a repo, what's a PR, what's hosting)
5. **Progress dashboards** — No "your project is 60% complete, here's what's left" visualization for non-technical users

---

## Gap Priority Matrix

| Gap | User Impact | Build Effort | Priority |
|-----|------------|-------------|----------|
| **Deployment guidance** | Critical (apps never ship) | High (many platforms) | **P1** |
| **Cross-project learning** | High (prevents repeated mistakes) | Medium | **P1** |
| **Hosting cost estimation** | High (surprise bills) | Medium | **P1** |
| **Non-technical onboarding** | High (blocks adoption) | High | **P2** |
| **RL from outcomes** | Medium (improves over time) | High | **P2** |
| **Vulnerability pattern DB** | Medium (proactive defense) | Medium | **P2** |
| **Live agent monitoring** | Medium (trust/visibility) | Medium | **P3** |
| **Circuit breaker** | Medium (safety) | Medium | **P3** |
| **Agent cost pre-flight** | Low (nice-to-have) | Low | **P3** |
| **User preference learning** | Low (personalization) | Medium | **P4** |
| **Visual project builder** | Low (alternative input) | High | **P4** |

---

## What to Build Next (Ordered)

### Phase 1: Close the "Ship It" Gap (Weeks 1-3)
1. **Deployment advisor** — Analyze project stack, recommend deployment platform, generate Dockerfile and CI config
2. **Hosting cost estimator** — Given project architecture, estimate monthly hosting costs on major platforms
3. **One-click deploy integration** — Partner with at least one platform (Railway/Render/Fly.io)

### Phase 2: Close the Learning Gap (Weeks 4-6)
4. **Cross-project vulnerability patterns** — Aggregate findings across projects into a shared pattern database
5. **Outcome-based reward signals** — Track deploy success/failure, test pass rates, and feed back into router scoring
6. **Expanded model pricing** — Cover Gemini, DeepSeek, Groq, Together, Cohere, local models

### Phase 3: Close the Accessibility Gap (Weeks 7-10)
7. **Plain English mode** — Translate all findings, errors, and suggestions into non-technical language
8. **Progress dashboard** — Visual "your project is X% complete" with remaining tasks
9. **Live agent activity feed** — Real-time view of what agents are doing

### Phase 4: Advanced (Weeks 11-16)
10. **RL-based self-improvement** — Proper reinforcement learning loop from real outcomes
11. **Circuit breaker** — Automatic agent shutdown on behavioral anomalies
12. **User preference adaptation** — Learn and apply user-specific patterns across sessions

---

## Summary

ControlKeel has **~75% of what the Pathfinder research recommends**. The core architecture (intent → plan → orchestrate → validate → govern) is fully built and production-quality. The major gaps are:

1. **Deployment guidance** (20% built) — The #1 blocker for vibe coders
2. **Learning/RL** (55% built) — Has memory and benchmarks but no true RL from outcomes
3. **Cost management** (60% built) — Has token tracking but no hosting cost estimation
4. **Non-technical UX** (30% built) — Has onboarding but no plain-English mode or visual builder

The good news: the foundation is solid. These gaps are all buildable on top of the existing architecture without major refactoring.
