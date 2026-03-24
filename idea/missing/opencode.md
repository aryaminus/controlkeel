## Completion status (non-Team P0)

Tracked against this file’s P0 list. Implementation lives in-repo; re-verify after large refactors.

| P0 theme | Status | Where to verify |
|----------|--------|-----------------|
| Provider + autonomy UX | Done | `lib/controlkeel_web/live/onboarding_live.ex` (`ProviderBroker.status/0`, mode labels, capability matrix, `provider_guidance`), `docs/getting-started.md`, `README.md` |
| Benchmark story publishable | Done | `docs/benchmarks.md`, `docs/examples/opencode-benchmark-subjects.json`, `lib/controlkeel_web/live/benchmarks_live.ex` |
| Release / ops | Documented | `docs/release-verification.md` — refresh GitHub SHAs when you cut a new release |
| Docs / UX consistency | Done | Mission Control uses packaged CLI (`controlkeel attach opencode`); terminology aligned in docs |
| Integration claims | Honest taxonomy | `lib/controlkeel/agent_integration.ex`, `docs/agent-integrations.md` |
| P1: Proxy surface | Done | `docs/agent-integrations.md` (exact `/proxy/...` paths; Mission Control `proxy_urls`) |
| P1: Autonomy policy | Done | `docs/autonomy-and-findings.md`, `README.md`, `Mission.finding_human_gate_hint/1`, onboarding + `/getting-started` |
| P1: Path graph UX | Done | `Mission.session_task_graph/1`, `lib/controlkeel_web/live/mission_control_live.ex` (dependencies + checklist) |
| P1: Advisory transparency | Done | `Scanner.Result.advisory`, `Advisory.advisory_status/3`, `POST /api/v1/validate`, MCP `ck_validate` |
| Max coverage (agents / MCP / skills / check.md) | Done | `docs/support-matrix.md`, `idea/missing/check.md` (classification table) |
| Benchmark UI presets | Done | `lib/controlkeel_web/live/benchmarks_live.ex` (quick presets, datalist), `docs/benchmarks.md` |

Optional ops (not code): run a packaged-binary smoke on current release artifacts when convenient; refresh SHAs in `docs/release-verification.md` after future releases.

P1 items in the long section below are addressed in-repo; deeper proxy routes or DAG editor UX would be follow-on work.

---

## Historical planning detail (archive)

The sections below (“Recommended Scope”, “Must-Finish”, phased build plans) are **archived planning text**. The **Completion status** table at the top of this file is authoritative for what shipped. Do not treat the long narrative as open work unless you explicitly open a new ticket.

**Max coverage inventory:** See [docs/support-matrix.md](../../docs/support-matrix.md) for agents, MCP tools, and bundled skills.

---

Recommended Scope
- Complete all remaining P0/P1 below.
- Do not treat the long agent list in idea/missing/check.md as required for completion.
- Do not reopen Team/Platform, JetStream-at-scale, or Tauri.
Must-Finish
- P0: Provider + Autonomy UX
  - Why: this is the biggest real gap from idea/missing/check.md:24.
  - Finish:
    - add a clear first-run provider decision flow in onboarding and getting-started
    - explicitly support 4 states: agent bridge, stored CK key, local Ollama, heuristic/no-model
    - explain which features degrade in heuristic mode
    - make “global attach vs per-project bootstrap” obvious
    - define default autonomous behavior: auto-fix low-risk, warn medium, escalate only destructive/high-risk actions
  - Evidence:
    - lib/controlkeel/provider_broker.ex
    - lib/controlkeel_web/live/onboarding_live.ex
    - lib/controlkeel_web/controllers/page_html/getting_started.html.heex
    - README.md
    - docs/getting-started.md
  - Exit criteria:
    - a novice can answer “do I need an API key?” in under 30 seconds
    - docs/UI all agree on fallback behavior
    - CK can run meaningfully with no key and tell the user exactly what is still available
- P0: Benchmark Story Must Become Publishable
  - Why: the product plan’s flywheel depends on this: idea/controlkeel-final-build-plan.md:563.
  - Finish:
    - ship at least one turnkey external benchmark path, not just CK-internal subjects
    - provide preconfigured external subject examples
    - make import/manual paths secondary, not primary
    - define the official benchmark suite and expected reporting format
    - document reproduction exactly
  - Evidence:
    - lib/controlkeel/benchmark/subject_loader.ex
    - lib/controlkeel/benchmark/runner.ex
    - lib/controlkeel_web/live/benchmarks_live.ex
    - priv/benchmarks/
  - Exit criteria:
    - third party can run CK vs at least one external agent with minimal setup
    - benchmark page no longer feels “internal only”
- P0: Release / Ops Completion
  - Why: this is still explicitly open in idea/missing/ck-final.md:71.
  - Finish:
    - confirm latest release-smoke and release are green
    - update release verification note
    - finalize release notes/changelog flow
    - confirm packaged install path works exactly as docs claim
  - Evidence:
    - .github/workflows/release.yml
    - .github/workflows/release-smoke.yml
    - docs/release-verification.md
    - README.md
  - Exit criteria:
    - one current known-good release SHA recorded
    - install-to-first-finding path verified on release artifacts
- P0: Docs / UX Consistency Cleanup
  - Why: trust breaks when UI/docs disagree.
  - Finish:
    - unify controlkeel attach ... vs mix ck.attach ... messaging by context
    - standardize terminology: attach, bootstrap, init, bridge, heuristic mode
    - make supported-agent matrix consistent everywhere
    - tighten claims around what is truly native vs MCP+instructions vs proxy
  - Evidence:
    - README.md
    - docs/getting-started.md
    - docs/agent-integrations.md
    - lib/controlkeel_web/live/mission_control_live.ex
    - lib/controlkeel_web/controllers/page_html/getting_started.html.heex
  - Exit criteria:
    - no contradictory setup advice across UI/docs
    - support claims are precise
- P0: Integration Claims Must Match Reality
  - Why: current story is broader than actual polished support.
  - Finish:
    - explicitly split agents into:
      - provider-bridge supported
      - MCP + native companion
      - MCP + instructions only
      - proxy-compatible
    - stop implying broad zero-config support where it is not yet true
    - define the blessed launch set
  - Evidence:
    - lib/controlkeel/agent_integration.ex
    - lib/controlkeel_web/router.ex
    - lib/controlkeel_web/controllers/proxy_controller.ex
  - Exit criteria:
    - product site/docs only promise what is operationally true
Nice-To-Have
- P1: Better Web-Agent / Proxy Coverage
  - broaden beyond current OpenAI/Anthropic-shaped proxy paths
  - make Bolt/Lovable/Replit/v0 setup more concrete
  - files: lib/controlkeel_web/router.ex, lib/controlkeel_web/controllers/proxy_controller.ex
- P1: Stronger Zero-Human-Intervention Policy Model
  - codify which findings auto-fix, auto-allow, auto-block, escalate
  - make the non-technical-user path feel automatic
  - files: policy packs, mission/finding flows, onboarding/docs
- P1: True Path Graph UX
  - current Mission Control is strong, but still closer to ordered tasks than full DAG
  - file: lib/controlkeel_web/live/mission_control_live.ex
- P1: Advisory Layer Polish
  - make provider-backed advisory behavior more explicit and consistent
  - file: lib/controlkeel/scanner/advisory.ex
Ignore For Now
- Team/shared workspace work
- org budgets / enterprise approvals
- more webhook/platform admin work
- NATS JetStream as a major deliverable
- Tauri desktop app
- long-tail agent/framework research list in idea/missing/check.md
- more domain packs beyond what already exists
Strong Recommendation
Build in this order:
1. Provider/autonomy UX
2. Benchmark publishability
3. Docs/claim consistency
4. Release verification
5. Proxy/integration expansion
6. Path-graph/advisory polish
Practical Definition Of “Complete”
I would call the non-Team work complete when all of these are true:
- a user can understand setup without asking about keys/providers
- CK works acceptably in bridge, key, Ollama, and heuristic modes
- benchmark can be reproduced against at least one real outside agent
- docs/UI all tell the same story
- release smoke and packaged install are verified current
- support claims are honest and narrow enough to defend
My Final Judgment
- Must finish before calling it complete: Provider UX, Benchmark credibility, Release verification, Docs/claims consistency
- Nice but not required for completion: more integrations, better DAG UX, advisory polish


====


Verdict
To “complete all that remains” without Team/Platform work, I recommend 3 build phases:
1. Phase A — close real product-completion gaps
2. Phase B — broaden and harden benchmark + integration coverage
3. Phase C — release, proof, and claim alignment
If we execute these, I’d be comfortable calling the non-Team product complete.
Phase A — Product Completion
This is the highest-value work. It resolves the unresolved UX questions in idea/missing/check.md:24.
- A1. Provider/autonomy UX end-to-end
  - Goal: answer, everywhere, “does CK need its own API key?”, “can it use the agent’s model?”, “what if user has no key?”, “can this be global?”
  - Implement:
    - explicit provider status card in onboarding review flow
    - visible capability states:
      - agent bridge
      - CK-owned profile
      - project override
      - local Ollama
      - heuristic
    - plain-language feature availability matrix:
      - governance/proofs/skills/benchmarks available in heuristic mode
      - model-backed compile/advisory/retrieval degrade
    - project-vs-global explanation:
      - agent attachment can be global/user scoped for some targets
      - governance binding remains project-local by design
    - autonomy defaults:
      - low-risk findings: auto-fix or warn
      - medium: warn with guided fix
      - destructive/high-risk: block/escalate
  - Files:
    - lib/controlkeel_web/live/onboarding_live.ex
    - lib/controlkeel/provider_broker.ex
    - lib/controlkeel/provider_config.ex
    - lib/controlkeel_web/controllers/page_html/getting_started.html.heex
    - README.md
    - docs/getting-started.md
    - docs/agent-integrations.md
  - Success criteria:
    - a new user can understand setup path in under 1 minute
    - no contradiction between docs/UI/runtime behavior
    - heuristic mode is clearly framed as first-class degraded mode, not failure
- A2. Make OpenCode a first-class blessed path
  - Goal: since you chose OpenCode, it should stop feeling like “instructions-only second tier”
  - Implement:
    - dedicated OpenCode getting-started guidance in docs
    - explicit OpenCode provider story
    - benchmark subject recipe for OpenCode
    - better attach verification text and launch UX
  - Files:
    - lib/controlkeel/agent_integration.ex
    - lib/controlkeel/cli.ex
    - docs/agent-integrations.md
    - docs/getting-started.md
    - maybe README.md
  - Success criteria:
    - OpenCode path is documented as a blessed target, not just listed
    - benchmark and attach workflows include OpenCode examples
- A3. UX consistency cleanup
  - Goal: one coherent story
  - Fix:
    - mix ck.attach claude-code message inside Mission Control should not be the primary generic CTA in app UI: lib/controlkeel_web/live/mission_control_live.ex:170
    - align packaged binary vs source-setup wording
    - unify terminology for attach, bootstrap, init, scope, bridge, heuristic
  - Files:
    - lib/controlkeel_web/live/mission_control_live.ex
    - lib/controlkeel_web/controllers/page_html/getting_started.html.heex
    - README.md
    - docs/getting-started.md
    - docs/agent-integrations.md
  - Success criteria:
    - all setup instructions are context-correct and consistent
Phase B — Benchmark + Integration Completion
This is the main “credibility” phase.
- B1. Make benchmark story externally credible
  - Problem today:
    - default subjects are internal only: lib/controlkeel/benchmark/subject_loader.ex:4
    - benchmark UI defaults to CK-vs-CK: lib/controlkeel_web/live/benchmarks_live.ex:490
  - Implement:
    - add a shipped sample external subject config for OpenCode
    - make benchmark UI expose external subject setup more clearly
    - provide official OpenCode vs ControlKeel benchmark path
    - improve run page language so placeholders/unconfigured subjects are obvious
  - Files:
    - lib/controlkeel/benchmark/subject_loader.ex
    - lib/controlkeel/benchmark/runner.ex
    - lib/controlkeel_web/live/benchmarks_live.ex
    - docs/demo-script.md
    - README.md
    - likely a new doc under docs/
    - likely sample config under repo docs/examples or similar
  - Success criteria:
    - someone can reproduce ControlKeel vs OpenCode without custom invention
    - benchmark defaults no longer feel purely internal
- B2. Tighten support taxonomy
  - Goal: support claims must match actual implementation
  - Split clearly:
    - provider-bridge supported
    - native-first MCP attach
    - repo-native
    - MCP + instructions
    - proxy-compatible
  - Files:
    - lib/controlkeel/agent_integration.ex
    - README.md
    - docs/agent-integrations.md
    - possibly lib/controlkeel_web/live/skills_live.ex
  - Success criteria:
    - every agent has an honest support class
    - no implied “full autonomy” where only instructions-only support exists
- B3. Proxy scope clarification and expansion
  - Current scope is narrower than the broader product pitch:
    - lib/controlkeel_web/router.ex:97
    - lib/controlkeel_web/controllers/proxy_controller.ex
  - Implement:
    - document exact supported proxy shapes now
    - optionally add one more concrete proxy-compatible path if feasible
    - state which web tools can use today’s proxy with minimal setup
  - Files:
    - lib/controlkeel_web/router.ex
    - lib/controlkeel_web/controllers/proxy_controller.ex
    - README.md
    - docs/getting-started.md
  - Success criteria:
    - no ambiguity around what “proxy support” means today
Phase C — Release + Proof-of-Ship Completion
This is the final closure phase.
- C1. Release verification completion
  - Goal: resolve the still-open ops tail from idea/missing/ck-final.md:71
  - Implement:
    - verify latest smoke/release status
    - update docs/release-verification.md
    - ensure getting-started paths match packaged artifacts
  - Files:
    - docs/release-verification.md
    - .github/workflows/release.yml
    - .github/workflows/release-smoke.yml
    - README.md
  - Success criteria:
    - one current known-good release is documented
    - packaged install path is confirmed current
- C2. Final product-positioning cleanup
  - Goal: make public claims defensible
  - Update:
    - README.md
    - key docs
    - maybe benchmark copy in UI
  - Specifically:
    - no overclaiming universal agent support
    - no overclaiming no-key autonomy
    - strong claim on what CK does well right now
What We Should Not Spend Time On
- Team/shared workspaces
- org policy/admin surfaces
- JetStream as a big standalone initiative
- Tauri desktop
- long-tail agent research list from idea/missing/check.md
- adding many more domain packs right now
Concrete Build Order
If you want me to execute efficiently, I would do this exact order:
1. Provider/autonomy UX
2. OpenCode-first docs + support story
3. Benchmark external-subject/OpenCode path
4. Docs/UI consistency cleanup
5. Proxy/support taxonomy cleanup
6. Release verification docs/finalization
Definition Of Done
I would call the non-Team work complete when these are all true:
- onboarding/docs clearly explain provider setup and no-key mode
- OpenCode is a fully documented first-class path
- benchmark supports a blessed OpenCode vs ControlKeel path
- docs/UI/support claims are aligned and honest
- release verification is current and documented
- heuristic mode and autonomy rules are explicit, not implicit
Recommendation For Build Mode
When we leave plan mode, I should execute in this pattern:
1. inspect current UX/docs points that need edits
2. implement Phase A fully
3. run mix precommit
4. implement Phase B
5. run mix precommit
6. finish Phase C
7. run mix precommit
8. review git diff and prepare commit(s)


====


Build Plan
- Objective: complete all meaningful remaining non-Team work so ControlKeel is product-complete, benchmark-credible, OpenCode-blessed, and launch-ready.
- Priority order: provider/autonomy UX → OpenCode path → benchmark credibility → docs/claim consistency → release verification.
Phase A — Provider + Autonomy Completion
- A1. Add first-run provider clarity to onboarding
  - Update lib/controlkeel_web/live/onboarding_live.ex
  - Add a provider-status panel to the review/final step using ProviderBroker.status/1
  - Show active source, fallback chain, attached agents, and a plain-language explanation
  - Add clear mode labels:
    - Bridge
    - CK key
    - Project override
    - Ollama
    - Heuristic
- A2. Define degraded-mode capability messaging
  - Reuse broker output from lib/controlkeel/provider_broker.ex
  - Document exactly what still works with no key/model:
    - governance
    - proofs
    - skills
    - MCP tools
    - benchmarks
  - Document what degrades:
    - advisory scans
    - model-backed compilation/help
    - any provider-backed intelligence
- A3. Answer global vs local setup clearly
  - Clarify in docs/UI:
    - agent attachment can be user/global for some targets
    - governed project binding remains project-local
  - Files:
    - README.md
    - docs/getting-started.md
    - docs/agent-integrations.md
    - lib/controlkeel_web/controllers/page_html/getting_started.html.heex
- A4. Define autonomous behavior policy
  - Make docs/product stance explicit:
    - auto-allow low-risk guidance tasks
    - auto-warn for medium-risk findings
    - auto-block/escalate destructive/high-risk actions
  - Wire this to current governance language without reopening Team approval systems
  - Files:
    - policy docs
    - onboarding copy
    - getting-started copy
    - maybe policy-pack docs/examples
Phase B — OpenCode First-Class Support
- B1. Promote OpenCode from “listed target” to blessed path
  - Current support exists in lib/controlkeel/agent_integration.ex
  - Add explicit docs section for OpenCode:
    - attach
    - config location
    - expected install artifacts
    - provider story
    - limitations vs bridge-native targets
- B2. Add OpenCode-first examples everywhere that matter
  - Files:
    - README.md
    - docs/getting-started.md
    - docs/agent-integrations.md
    - maybe docs/demo-script.md
- B3. Tighten agent taxonomy
  - In docs and maybe API-facing summaries, split agents into:
    - provider-bridge supported
    - native-first
    - repo-native
    - MCP + instructions
    - proxy-compatible
  - Evidence source:
    - lib/controlkeel/agent_integration.ex
Phase C — Benchmark Completion
- C1. Make external benchmarking feel real, not manual-only
  - Current defaults are internal-only:
    - lib/controlkeel/benchmark/subject_loader.ex
    - lib/controlkeel_web/live/benchmarks_live.ex:490
  - Add a blessed OpenCode benchmark path
  - Ship example external-subject config for OpenCode
- C2. Improve benchmark UX
  - In lib/controlkeel_web/live/benchmarks_live.ex
  - Replace freeform “Subjects” and “Baseline subject” text inputs with better guided hints or selectable known subjects if feasible
  - Surface configured/unconfigured state clearly
  - Add notes for import/manual subject limitations
- C3. Define official reproducible benchmark recipe
  - Add docs for:
    - benchmark subject config
    - OpenCode execution path
    - expected output/import path
    - how to compare results credibly
  - Files:
    - new benchmark doc
    - docs/demo-script.md
    - README.md
- C4. Keep benchmark claims honest
  - Keep public wording to “blessed OpenCode comparison path”
  - Do not imply universal plug-and-play external benchmarking
Phase D — Docs + UI Consistency Cleanup
- D1. Fix mixed CLI messaging
  - lib/controlkeel_web/live/mission_control_live.ex:170 currently points to mix ck.attach claude-code
  - App UI should prefer packaged CLI wording unless explicitly in source-dev mode
- D2. Standardize vocabulary
  - Normalize:
    - attach
    - bootstrap
    - init
    - provider bridge
    - heuristic mode
    - user/project scope
- D3. Align support claims everywhere
  - Files:
    - README.md
    - docs/getting-started.md
    - docs/agent-integrations.md
    - getting started HEEx
    - benchmark UI copy if needed
Phase E — Proxy + Support Surface Cleanup
- E1. Clarify what proxy supports today
  - Current router/controller support is specific:
    - lib/controlkeel_web/router.ex:97
    - lib/controlkeel_web/controllers/proxy_controller.ex
  - Document exact current compatibility instead of broad implication
- E2. Optionally add one more concrete proxy recipe
  - Only if low-risk and fast
  - Otherwise document current OpenAI/Anthropic shape clearly
Phase F — Release Completion
- F1. Final release-verification pass
  - Verify current release/smoke status outside code edits when implementation is done
  - Update docs/release-verification.md
- F2. Align packaged install docs
  - Ensure release docs, README, and in-app getting-started all match the actual artifact flow
- F3. Prepare final launch positioning
  - Product claims should match actual completed support
Suggested File Map
- Provider/autonomy:
  - lib/controlkeel_web/live/onboarding_live.ex
  - lib/controlkeel/provider_broker.ex
  - lib/controlkeel/provider_config.ex
- OpenCode/integration docs:
  - lib/controlkeel/agent_integration.ex
  - README.md
  - docs/getting-started.md
  - docs/agent-integrations.md
- Benchmarks:
  - lib/controlkeel/benchmark/subject_loader.ex
  - lib/controlkeel/benchmark/runner.ex
  - lib/controlkeel_web/live/benchmarks_live.ex
  - priv/benchmarks/*.json
  - new benchmark doc/example config
- UI consistency:
  - lib/controlkeel_web/live/mission_control_live.ex
  - lib/controlkeel_web/controllers/page_html/getting_started.html.heex
- Proxy/release:
  - lib/controlkeel_web/controllers/proxy_controller.ex
  - lib/controlkeel_web/router.ex
  - docs/release-verification.md
Verification Plan
- After each phase:
  - mix precommit
- After benchmark phase:
  - run benchmark flow with blessed OpenCode subject
- After docs/UI phase:
  - sanity-check every setup path for consistency
- Final:
  - release-smoke/release verification
  - git diff review
  - final completeness audit
Definition Of Done
- onboarding explains provider/no-key/global-vs-project setup clearly
- OpenCode is a first-class blessed target
- external benchmark path exists and is reproducible
- docs/UI all agree
- proxy claims are precise
- release verification is current
- product claims are honest and defensible
Recommendation
When you switch out of plan mode, I should execute in this order:
1. Phase A
2. mix precommit
3. Phase B + C together
4. mix precommit
5. Phase D + E
6. mix precommit
7. Phase F
8. final audit + commit prep