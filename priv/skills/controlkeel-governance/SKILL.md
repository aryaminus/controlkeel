---
name: controlkeel-governance
description: "Interact with ControlKeel's governance layer: validate code before execution, report findings, track budget, fetch mission context, and route tasks to the best agent. Use this skill whenever you are working inside a ControlKeel-governed session."
license: Apache-2.0
metadata:
  author: controlkeel
  version: "1.0"
compatibility: Designed for any MCP-capable agent (Claude Code, Cursor, Kiro, etc.)
allowed-tools: ck_validate ck_context ck_finding ck_budget ck_route ck_skill_list ck_skill_load
---

# ControlKeel Governance Skill

You are operating inside a **ControlKeel-governed session**. ControlKeel is a control plane that runs above your actions to enforce security policy, track budget, and surface audit findings to the human operator.

## When to Use Each Tool

### ck_validate — Before Writing or Executing
Call `ck_validate` before writing any code, config, shell command, or text that will be executed or deployed.

```
ck_validate({
  "content": "<the code or config to validate>",
  "kind": "code" | "config" | "shell" | "text",
  "session_id": <session_id>,
  "task_id": <task_id>
})
```

- If `allowed: true` → proceed.
- If `allowed: false` → **stop**. Report the blocking finding to the user. Do not proceed until the human approves.
- Findings with `decision: "warn"` → continue but note the warning in your response.

### ck_context — Mission Briefing
Call `ck_context` at session start and whenever you need to understand the current mission, risk tier, budget, or active findings.

```
ck_context({"session_id": <session_id>})
```

Use the returned `risk_tier` to calibrate how cautious you are:
- `critical` → require human approval before any irreversible action
- `high` → validate all external calls, document all changes
- `medium` → validate code and config; proceed with care
- `low` → standard workflow, validate before deploy

### ck_finding — Report Governance Issues
Call `ck_finding` when you detect a potential problem that the human should review, even if the scanner didn't catch it.

```
ck_finding({
  "session_id": <session_id>,
  "category": "security" | "compliance" | "cost" | "privacy" | "quality",
  "severity": "critical" | "high" | "medium" | "low",
  "rule_id": "your.rule.identifier",
  "plain_message": "Plain English description of the issue",
  "decision": "warn" | "block" | "escalate_to_human"
})
```

### ck_budget — Cost Awareness
Call `ck_budget` before expensive operations (large model calls, bulk processing) to check remaining budget.

```
ck_budget({
  "session_id": <session_id>,
  "mode": "estimate",
  "estimated_cost_cents": <estimate>,
  "provider": "anthropic" | "openai" | ...
})
```

If `allowed: false` → do not proceed with the expensive operation.

### ck_route — Agent Selection
Call `ck_route` when you need to delegate a sub-task to the most appropriate agent.

```
ck_route({
  "task": "Deploy the staging environment",
  "risk_tier": "high",
  "budget_remaining_cents": 5000
})
```

### ck_skill_list / ck_skill_load — Skill Discovery
- Call `ck_skill_list` to discover available skills for this project.
- Call `ck_skill_load` with a skill name to load detailed instructions.

## Governance Rules

1. **Never skip validation** — always call `ck_validate` before writing files or executing shell commands in a governed session.
2. **Respect blocks** — a `blocked` finding means stop immediately.
3. **Surface findings** — do not hide policy warnings from the human operator.
4. **Stay within budget** — check `ck_budget` before any operation estimated above $0.10.
5. **Risk-aware behavior** — at `critical` risk tier, explicitly confirm with the human before any destructive or irreversible action.

## Quick Reference

| Tool | When to call |
|------|-------------|
| `ck_validate` | Before any code write, shell exec, or deploy |
| `ck_context` | Session start, task switch, or when unsure of constraints |
| `ck_finding` | When you detect a policy issue or anomaly |
| `ck_budget` | Before expensive LLM calls or bulk operations |
| `ck_route` | When delegating sub-tasks to other agents |
| `ck_skill_list` | To discover available capabilities |
| `ck_skill_load` | To activate a specific skill's instructions |
