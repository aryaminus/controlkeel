
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