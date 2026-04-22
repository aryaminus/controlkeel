# Autonomy and findings

ControlKeel records findings and can suggest fixes, but it does **not** promise fully unsupervised autonomy for every risk level. Use this page as the single reference for how severity maps to expected human involvement.

CK now also exposes a **session autonomy profile** and an **outcome profile**. That is how ControlKeel makes the operator model explicit instead of implying that every governed session is the same.

## Session autonomy profiles

These are session-level operating modes, distinct from host integration autonomy labels such as `policy_gated` in the support matrix.

| Session mode | Meaning |
|----------|----------------|
| **advise** | CK is helping plan, review, and package context, but the human is still steering each step. |
| **supervised_execute** | The agent can execute, but high-risk or approval-heavy work keeps human gates close to the loop. |
| **guarded_autonomy** | The default CK operating mode: agents can work, while findings, proofs, budgets, and routing controls remain active. |
| **long_running_autonomy** | The session is keyed to an explicit outcome/KPI or sustained multi-task objective, so CK treats it as an ongoing improvement loop. |

These profiles are derived from explicit metadata when present, and otherwise inferred from risk, constraints, cyber access mode, and session shape.

## Outcome profiles

CK distinguishes between:

- **delivery** sessions: complete the current task or release milestone safely
- **kpi** sessions: move an explicit outcome target such as reducing a vulnerability backlog or reaching deploy-ready with no critical findings

That profile is now surfaced in:

- MCP `ck_context`
- `GET /api/v1/sessions`
- `GET /api/v1/sessions/:id`
- `GET /api/v1/improvement`
- `/ship`

So operators can tell whether a session is just trying to finish work, or whether it is meant to run as a longer-horizon control loop.

The session improvement loop also exposes two software-law diagnostics:

- `bottleneck_summary` identifies the likely serial constraint before CK recommends more parallel work. It distinguishes unresolved findings, pending review readiness, missing deploy-ready proof, budget pressure, and thin trace evidence.
- `ownership_summary` reports concentration across available task owners, review submitters, and finding categories. It is intentionally evidence-backed and only warns when the current data shows enough concentration to be useful.

Both diagnostics also provide CK-style `diagnostic_findings` payloads. CK does not auto-persist them by default, which avoids duplicate findings during normal dashboard refreshes; callers can persist them when they want a durable review item.

## Provider-backed vs heuristic mode

- **LLM advisory** (extra pattern review on top of FastPath and Semgrep) runs only when a provider is configured. Validate and MCP `ck_validate` responses include an **`advisory`** object describing whether the advisory layer ran or was skipped (for example no API key).
- **Heuristic mode** still supports governance, MCP tools, proofs, skills, and benchmarks; model-backed advisory and some compilation paths are limited.
- **Destructive shell tripwires** run even in heuristic mode. Repo-wide cleanup commands such as `git checkout -- .`, `git reset --hard`, `git clean -fd`, and broad `rm -rf` scopes are blocked with checkpoint and rollback guidance so agents cannot treat them as ordinary shell mutations.

## Severity and default gates

These are **product expectations** for reviewers, not automatic enforcement rules in every deployment:

| Severity | Typical gate |
|----------|----------------|
| **critical** | Human review required before production or high-impact action. |
| **high** (especially security) | Review and approve before merge or release. |
| **high** (non-security) | Review recommended before marking work complete. |
| **medium** | Review when convenient; guided fixes and warnings are common. |
| **low** | Governance still records outcomes; lower friction. |

Destructive or irreversible actions should stay behind explicit approval, proofs, and policy—regardless of severity.

## Human wake-up surfaces

CK is designed to preserve a few places where the human should wake back up instead of letting the agent loop stay frictionless.

That expectation already shows up in the product through:

- `human_gate` execution modes for review/release-oriented task nodes
- architecture-first planning for higher-risk work
- rollback boundaries on task plans
- human gate hints attached to findings in Mission Control

In practice, CK is telling the operator not to treat every generated diff the same. Narrow, reversible fixes can stay low-friction. Architecture decisions, release-boundary changes, destructive actions, and similarly high-consequence changes should pull the human back into the loop.

CK does not claim to perfectly classify every risky change type today. The current product stance is narrower and more honest: keep the review boundary explicit, keep rollback and proof state visible, and increase human attention as impact and irreversibility go up.

Plan reviews now also include decision hygiene prompts in review-gate metadata. These prompts are tied to concrete signals such as high scope, missing validation evidence, repeated plan depth, or missing rejected options. They are designed to trigger inversion, evidence, sunk-cost, and alternative checks without turning the UI into generic advice.

## Relation to Mission Control

Mission Control surfaces **human gate hints** next to each finding so operators see the same stance the docs describe. Approve, reject, and proof flows remain the source of truth for recorded decisions.
