---
name: cost-optimization
description: "Monitor and optimize AI agent run costs within a ControlKeel session. Use this skill to estimate operation costs, check remaining budget, split expensive tasks, and prevent runaway spend. Activate whenever the session budget is under pressure or before launching a long-running agent operation."
license: Apache-2.0
metadata:
  author: controlkeel
  version: "1.0"
compatibility: Works with any agent that has access to ck_budget and ck_context MCP tools
---

# Cost Optimization Skill

## Budget Awareness Protocol

### Step 1: Check Budget Before Any Operation
Always check remaining budget before a costly operation:

```
ck_budget({
  "session_id": <id>,
  "mode": "estimate",
  "estimated_cost_cents": <your estimate>,
  "provider": "anthropic" | "openai" | "bedrock" | ...
})
```

If `remaining_session_cents < estimated_cost_cents` → **do not proceed**. Report to human.
If `remaining_daily_cents < estimated_cost_cents` → **do not proceed**. Report daily cap hit.

### Step 2: Commit Actual Cost After Operation
After an operation completes, record actual cost:

```
ck_budget({
  "session_id": <id>,
  "mode": "commit",
  "input_tokens": <actual>,
  "output_tokens": <actual>,
  "provider": "anthropic",
  "model": "claude-opus-4-6"
})
```

## Cost Estimation Guide

| Operation | Typical cost (cents) |
|-----------|---------------------|
| Small code edit (< 2k tokens) | 1–3 ¢ |
| Medium task (2k–10k tokens) | 5–20 ¢ |
| Large refactor (10k–50k tokens) | 20–100 ¢ |
| Full codebase analysis (50k+ tokens) | 100–500 ¢ |
| Managed platform run (Bedrock Agents, Azure AI Agent) | 500–2000 ¢ |

## Cost Reduction Strategies

### 1. Cache-First
- Use cached context (input_tokens → cached_input_tokens) for repeated operations
- Reuse session context from `ck_context` rather than re-fetching

### 2. Task Splitting
- Break large tasks into smaller sub-tasks with their own budget slices
- Stop after each sub-task and report progress before continuing

### 3. Model Selection
- Use smaller/cheaper models for simple tasks (classification, formatting)
- Reserve large models for reasoning-heavy tasks
- Call `ck_route` to get a cost-aware agent recommendation:
  ```
  ck_route({
    "task": <description>,
    "risk_tier": <tier>,
    "budget_remaining_cents": <remaining>
  })
  ```

### 4. Early Exit
- If a task is growing unexpectedly expensive, stop and report to human
- Prefer incremental commits over one large operation

### 5. Avoid Redundant Validation
- Cache `ck_validate` results within a single task if the content hasn't changed
- Do not re-validate the same content block multiple times

## Budget Warning Thresholds

ControlKeel automatically warns at 80% budget usage and blocks at 100%. Proactively manage spend to stay under 75% and leave headroom for validation overhead.

## When Budget Is Critical

If `remaining_session_cents < 500` (under $5):
1. Call `ck_context` to confirm remaining budget
2. Only proceed with operations under 50 cents
3. Inform the human of the budget state before each significant operation
4. Recommend the human add budget via the Mission Control UI before continuing
