# Autonomy and findings

ControlKeel records findings and can suggest fixes, but it does **not** promise fully unsupervised autonomy for every risk level. Use this page as the single reference for how severity maps to expected human involvement.

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
