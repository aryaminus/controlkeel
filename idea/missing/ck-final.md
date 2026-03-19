
     ---
     What Is Missing / Incomplete

     MVP Gaps (blocks external launch)

     1. Policy Studio LiveView — MISSING ENTIRELY

     The 5th planned screen. No route, no file, no UI.
     Purpose: show active policy packs, budget limits, edit thresholds. Non-technical users need to know what's being enforced.
     Minimum viable: read-only view of active packs + budget sliders per session/day.
     Files to create: lib/controlkeel_web/live/policy_studio_live.ex, route /policies in router.ex.

     2. Proof Bundle — NOT BUILT

     The plan says every completed task produces a structured proof bundle with test_outcomes, diff_summary, risk_score, deploy_ready, rollback_instructions, compliance_attestations.
     Current state: tasks have a validation_gate text field (e.g., "Security scan and proof bundle") but it's never enforced. Tasks can be marked done with no evidence.
     Minimum viable: attach finding summary + auto-fix resolution status to task completion. Block "mark done" if open/blocked findings exist.

     3. Budget Slider in Onboarding — MISSING

     The plan says Step 1 includes a "$0 to $100/day slider with plain-language cost examples." Currently onboarding only asks occupation + agent. Budget is never set in the UI; it defaults to whatever
     planner.ex derives from the brief.
     Fix: Add budget input to Step 1 of OnboardingLive, wire through to session creation attrs.

     4. Approve/Reject UI in Mission Control — NOT WIRED

     The API exists (POST /api/v1/findings/:id/action). Mission.approve_finding/1 and Mission.reject_finding/2 exist. But MissionControlLive shows findings as text only — no approve/reject buttons. Users have to
      use the separate /findings page.
     Fix: Add approve/reject event handlers + buttons to MissionControlLive.

     5. REST API Tests — MISSING

     api_controller.ex was just created. No test/controlkeel_web/controllers/api_controller_test.exs exists.

     ---
     UX Polish Gaps (blocks non-technical user demo)

     6. Path Graph / Task Status Visualization — PLACEHOLDER

     Mission Control shows a stat card for "tasks" but no visual task list with status progression. Tasks exist in the DB with status (queued/in_progress/done) and position but there's no visual representation
     in the UI.
     No DAG engine needed — a simple ordered list with status badges and validation gates is sufficient for MVP.

     7. Compliance Score Donut — MISSING

     The plan specifically mentions a compliance score donut in Mission Control. Currently only a finding count badge exists.

     8. Onboarding: No "You're set" confirmation screen

     After brief compilation, the user sees the brief and clicks "Start Mission." There's no clear "mission created" success state — the redirect to /missions/:id should show a welcome/setup confirmation.

     ---
     What Is Deliberately Phase 2 (Do Not Build Now)

     - Layer 3: Agent Router — no routing engine, user selects agent manually. Acceptable for MVP.
     - Layer 6: Memory System — episodic records exist in DB, no pgvector/semantic memory, no RL. Phase 2.
     - Bakeware binary packaging — configured in mix.exs but not tested. Phase 2 / pre-launch.
     - LLM Advisory (3rd tier scanner) — not implemented. FastPath + Semgrep is sufficient for MVP.
     - Audit Log PDF export — Phase 2 enterprise feature.
     - Multi-agent routing — Phase 2.

     ---

What remains is Phase 2:                                                                                                                                                                                         
                                                                                                                                                                                                                   
  ┌───────────────────────────┬───────────────────────────────────────────────────────────────┬──────────────┐                                                                                                     
  │           Item            │                             Value                             │  Complexity  │                                                                                                     
  ├───────────────────────────┼───────────────────────────────────────────────────────────────┼──────────────┤                                                                                                     
  │ Wire watch into CLI.parse │ Completes binary parity with mix tasks                        │ Low (30 min) │
  ├───────────────────────────┼───────────────────────────────────────────────────────────────┼──────────────┤
  │ Semgrep rule expansion    │ More language-specific catches (React, Go, Rust)              │ Medium       │                                                                                                     
  ├───────────────────────────┼───────────────────────────────────────────────────────────────┼──────────────┤                                                                                                     
  │ Layer 3: Agent Router     │ Auto-select best agent for a task type                        │ High         │                                                                                                     
  ├───────────────────────────┼───────────────────────────────────────────────────────────────┼──────────────┤                                                                                                     
  │ Layer 6: Memory System    │ pgvector semantic memory, episodic records, RL policy         │ Very high    │
  ├───────────────────────────┼───────────────────────────────────────────────────────────────┼──────────────┤                                                                                                     
  │ LLM Advisory scanner      │ 3rd tier after FastPath + Semgrep for context-aware decisions │ High         │
  ├───────────────────────────┼───────────────────────────────────────────────────────────────┼──────────────┤                                                                                                     
  │ Audit Log PDF export      │ Enterprise compliance reporting                               │ Medium       │
  ├───────────────────────────┼───────────────────────────────────────────────────────────────┼──────────────┤                                                                                                     
  │ Multi-tenant / auth       │ User accounts, org-level sessions                             │ High         │
  ├───────────────────────────┼───────────────────────────────────────────────────────────────┼──────────────┤                                                                                                     
  │ Burrito binary smoke test │ Verify the packaged binary actually boots                     │ Low          │

- Ship it → do the Burrito smoke test, tag v0.1.0, write a changelog                                                                                                                                             
  - Go deeper on security → LLM Advisory scanner            
  - Go wider → auth + multi-tenant so others can use it   

 │           Item            │                        What it unlocks                         │ Complexity │
  ├───────────────────────────┼────────────────────────────────────────────────────────────────┼────────────┤
  │ Burrito binary smoke test │ Confirms controlkeel binary actually boots before shipping     │ Low        │
  ├───────────────────────────┼────────────────────────────────────────────────────────────────┼────────────┤
  │ LLM Advisory scanner      │ 3rd tier — context-aware decisions FastPath+Semgrep can't make │ High       │
  ├───────────────────────────┼────────────────────────────────────────────────────────────────┼────────────┤
  │ Agent Router (Layer 3)    │ Auto-select best agent by task type                            │ High       │
  ├───────────────────────────┼────────────────────────────────────────────────────────────────┼────────────┤
  │ Auth / multi-tenant       │ Multiple users, org sessions, API keys                         │ High       │
  ├───────────────────────────┼────────────────────────────────────────────────────────────────┼────────────┤
  │ Memory System (Layer 6)   │ pgvector semantic memory, episodic records, RL policy tuning   │ Very high  │
  ├───────────────────────────┼────────────────────────────────────────────────────────────────┼────────────┤
  │ Audit Log PDF export      │ Enterprise compliance reporting                                │ Medium     │

    1. ck init requires a separate ck attach step — Plan says init auto-registers. Currently creates the project binding only; user must discover they need ck attach claude-code separately. This breaks the
     10-minute onboarding goal.
     2. Proof Bundle missing test_outcomes and diff_summary — The plan's proof bundle spec requires both fields. Currently only invocation_count and security_findings are returned. Data exists in DB; it just
     isn't mapped to the spec'd shape.
     3. Tasks missing confidence_score and rollback_boundary — Plan says each path graph node has these. The Task schema and planner don't generate them. Low-risk fix: add migration + planner generation + expose
      in Mission Control.

     Everything else flagged as "MISSING" in the audit is explicitly Phase 2 (pgvector, DAG edges, RL) per the plan's "What to NOT build in MVP" section.

     ---
     Files to Modify

       What's intentionally deferred (Phase 2):                                                                                                                                                                         
  - pgvector semantic search                                                                                                                                                                                       
  - Task DAG edges / parallel execution                                                                                                                                                                            
  - RL policy training inference                                                                                                                                                                                   
  - Audit Log PDF export (Phase 3)                                                                                                                                                                                 
  - Multi-tenant org isolation      

       4. MISSION PLANNER (lib/controlkeel/mission/planner.ex)

       Status: FULLY IMPLEMENTED heuristic-based planner (NOT ML-driven)

       mission/planner.ex (599 lines) — Complete:

       Sophistication Level: Rule-based Heuristics
       - NOT ML-driven; purely deterministic logic
       - Hard-coded industry profiles: 12 profiles (web, health, finance, ecommerce, education, legal, hr, marketing, sales, realestate, iot, general)
       - Agent label map: 150+ known agents (Claude Code, Cursor, OpenAI, Anthropic, etc.)

       Architecture: Builds mission context from user input:
       attrs → industry/agent/idea/features/budget/data → risk tier → compliance → stack recommendation

       Risk Tier Logic (lines 332-365) — Rule-based:
       health/finance/legal → "critical"
       hr/realestate → "high"
       marketing/sales with specific keywords → "high" (conditionally)
       payment/medical/salary keywords → "critical"
       personal/account/auth keywords → "high"
       default → "moderate"

       Compliance Generation (lines 368-383):
       - Base from industry profile (e.g., HIPAA for health)
       - Adds extra rules if data mentions: email/PII, medical, payment

       Stack Recommendation (lines 385-388):
       - If critical risk: append "require human approval before deploy"
       - Otherwise, use industry profile stack as-is

       Task Generation (lines 417-461):
       - Builds task list from features (max 5 features)
       - Pre-populates: architecture, feature tasks, release checklist
       - Status: "done", "in_progress", "queued"
       - Estimated costs hardcoded: 15¢ (arch), 35¢ (features), 20¢ (release)
       - Confidence scores: 0.9 (arch), 0.75 (feature), 0.85 (verify) adjusted by risk tier

       Finding Generation (lines 488-550):
       - 5 conditional findings based on keywords in content
       - Budget guard (always included)
       - Auth review, payment isolation, health data, file upload findings

       Key Finding: This is RULE-BASED ONLY. No machine learning. The planner reads input, applies keyword matching, and generates deterministic outputs. Confidence scores and budgets are hardcoded
       heuristics. This is appropriate for onboarding but lacks learned personalization.

       1. No ML in Mission Planner — The planner is rule-based heuristics (keyword matching, hard-coded tiers). The learned policy lives in agent routing only.
       2. Learned Policies are Optional — Both agent router and budget decisions gracefully fall back to heuristics if no active artifact exists. This is good for bootstrapping.

 Deployment Risk │ 🟡 Low              │ Ready for staging → requires final env/security checklist