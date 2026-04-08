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

## Relation to Mission Control

Mission Control surfaces **human gate hints** next to each finding so operators see the same stance the docs describe. Approve, reject, and proof flows remain the source of truth for recorded decisions.
