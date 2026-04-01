# Gap Analysis: ControlKeel vs Pathfinder Research

Updated: 2026-03-30

## Scorecard

| Dimension | Before | Current | Status |
| --- | ---: | ---: | --- |
| Intent engine and planning | 90% | 90% | Strong baseline retained |
| Agent orchestration | 85% | 85% | Strong baseline retained |
| Security and validation | 80% | 80% | Strong baseline retained |
| Compliance coverage | 90% | 90% | Strong baseline retained |
| Governance and guardrails | 85% | 95% | Improved |
| Learning and memory | 55% | 90% | Improved |
| Cost management | 60% | 90% | Improved |
| Deployment guidance | 20% | 90% | Improved |
| Multi-agent support | 95% | 95% | Strong baseline retained |
| Distribution channels | 90% | 90% | Strong baseline retained |

Estimated overall coverage moved from about 75% to about 90%.

## Dimensions Already Strong

These dimensions were already in a strong state and remain that way:

1. Intent engine and planning
2. Agent orchestration
3. Security and validation
4. Compliance coverage
5. Multi-agent support
6. Distribution channels

## Major Improvements Completed

### 1) Learning and memory (55% -> 90%)

Key modules:

- Learning.OutcomeTracker
- Learning.CrossProject
- Learning.PreferenceAdapter

What is now covered:

1. Outcome-reward tracking and agent scoring over time.
2. Agent leaderboards and router-weight support for performance-aware routing.
3. Cross-project finding aggregation and recurring-pattern lookup.
4. Preference detection and preference injection into planning briefs.

### 2) Cost management (60% -> 90%)

Key modules:

- Budget.Pricing
- Budget.SpendAlerts
- Budget.CostOptimizer
- Deployment.HostingCost

What is now covered:

1. Broader model-pricing coverage (multi-provider).
2. Budget threshold alerts with burn-rate detection.
3. Cost optimization suggestions (model choice, batching, caching, local model use).
4. Hosting cost comparison across major platforms.
5. Agent-level cost comparison for pre-flight planning.

### 3) Deployment guidance (20% -> 90%)

Key modules:

- Deployment.Advisor
- Deployment.HostingCost
- ControlKeelWeb.DeploymentLive

What is now covered:

1. Stack-aware Docker and compose guidance.
2. Platform recommendation and cost-aware deployment choices.
3. CI/CD guidance generation by stack.
4. Environment variable setup templates.
5. Database migration guidance by stack.
6. DNS/SSL guidance and post-deploy readiness checks.
7. Deploy-focused LiveView UX for analysis and preview.

### 4) Governance hardening (85% -> 95%)

Key modules:

- Governance.CircuitBreaker
- Governance.AgentMonitor
- Governance.PreCommitHook

What is now covered:

1. Runtime policy interruption for risky behavior patterns.
2. Better agent execution visibility and event telemetry.
3. Stronger pre-commit enforcement before unsafe changes land.

## Non-Technical UX Progress

Current level: about 70%

Now covered:

1. Guided onboarding and intent capture.
2. Mission planning from structured specs.
3. Plain-language finding explanations.
4. Session progress visibility and remaining-work signals.

Still out of scope in this phase:

1. Visual drag-and-drop project builder.
2. One-click hosted deploy via first-party partner APIs.
3. Full tutorial/content curriculum for novice workflows.

## Remaining P4 Items

The remaining items are productization-heavy, not core-engine gaps:

1. Visual project builder.
2. One-click deploy integrations.
3. Guided tutorial system.

## Verification Notes

Previous validation cycles reported compile, tests, and precommit passing after the related feature work.
This document reflects capability coverage and architecture state; run the current branch validation again before release.

## Conclusion

ControlKeel now covers nearly all high-impact Pathfinder recommendations in code and workflow terms.
The unresolved items are mostly UX-product packaging and ecosystem integration work rather than missing governance architecture.
