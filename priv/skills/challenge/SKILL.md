---
name: challenge
description: "Adversarially challenge the current plan or finding. Assume the direction is wrong and build the strongest case against it. Surfaces blind spots, false assumptions, and unexplored alternatives before execution starts."
when_to_use: "Activate when the user says 'challenge this', 'push back', 'what could go wrong', 'steelman against', or 'devil's advocate'. Also activate before executing a high-depth or high-scope plan (depth >= 5, scope architectural_scope=true). Use after ck_review_submit to stress-test an approved plan before coding starts."
argument-hint: "[plan review_id or finding rule_id to challenge — omit to challenge the latest approved plan]"
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - opencode-native
  - cursor-native
  - windsurf-native
  - continue-native
  - cline-native
  - roo-native
  - goose-native
  - antigravity-cli-native
  - kiro-native
  - amp-native
  - augment-native
metadata:
  author: controlkeel
  version: "1.0"
  category: governance
  ck_mcp_tools:
    - ck_context
    - ck_finding
    - ck_review_status
---

# Challenge Skill

Adversarially review the current plan or a specific finding. The goal is not to block work — it is to surface the strongest objections *before* execution so they can be addressed, not discovered mid-implementation.

Inspired by Paradigma/Flywheel's adversarial review nodes: every knowledge claim should have an adversarial pass that tries to refute it before it propagates downstream.

## When to Use

- Before executing a plan with `architectural_scope: true` or `depth >= 5`
- When the user asks "what could go wrong", "push back on this", or "devil's advocate"
- After `ck_review_submit` on a plan that affects multiple files or core modules
- When a finding has been open for multiple sessions and no one has questioned it
- Before delegating long-running autonomous work

## Challenge Flow

### Step 1 — Load context

Call `ck_context` to load:
- The current session, task, and latest approved plan
- Open findings (especially `blocked` and `escalated`)
- Risk tier and compliance constraints

If a specific `review_id` or `rule_id` was passed as an argument, use that as the target. Otherwise challenge the latest approved plan from `planning_context.latest_approved_plan`.

### Step 2 — Extract the hypothesis

Look for `hypothesis` and `expected_signal` in the plan refinement. If absent, infer them:
- **Hypothesis**: what core assumption does this plan rest on? (e.g. "adding X will fix Y", "this abstraction won't break Z")
- **Expected signal**: what would confirm the hypothesis is correct?

State both explicitly before challenging. If you cannot reconstruct a hypothesis, that itself is the first challenge: **"This plan has no falsifiable hypothesis."**

### Step 3 — Run the adversarial pass

For each dimension below, generate the strongest objection you can. Do not hedge — argue as if you are trying to kill the plan.

#### A. Assumption inversion
List the top 3 assumptions the plan makes. For each, ask: "What if this is false?" If any assumption being false would make the plan fail or significantly change the approach, flag it.

#### B. Scope creep signal
Look at `scope_estimate`. Is `architectural_scope` underreported? Are there more files likely to be touched than `files_touched_estimate` suggests? Flag any evidence that the real diff will be larger than claimed.

#### C. Contradicted findings
Check existing findings. Does any open finding (status `open` or `blocked`) directly contradict or undermine the plan? List them with their `rule_id`.

#### D. Missing alternatives
Look at `options_considered` and `rejected_options`. Is there a viable approach that was never considered? Describe it in one sentence and state why it might be better.

#### E. Validation gap
Look at `validation_plan`. Is there a scenario where all validation steps pass but the plan still fails in production? Describe it.

#### F. Hallucination propagation risk
If this plan produces outputs that downstream tasks will depend on — identify what those outputs are and whether they are verifiable. Flag any output that downstream work will treat as ground truth but that has not been independently verified.

### Step 4 — Score the challenge

Summarize findings as:

```
STRONG objections (would change the plan):   N
MODERATE objections (should be addressed):   N
WEAK objections (worth noting, not blocking): N
```

If `STRONG >= 1`: recommend **blocking execution** and re-submitting the plan with the objections addressed.
If `STRONG == 0, MODERATE >= 2`: recommend **addressing before execution starts**, not blocking.
If `STRONG == 0, MODERATE <= 1`: recommend **proceeding** with the noted caveats.

### Step 5 — Record findings

For each STRONG or MODERATE objection, call `ck_finding` with:
- `category`: `"challenge"`
- `severity`: `"high"` for STRONG, `"medium"` for MODERATE
- `rule_id`: `"challenge.<dimension>"` (e.g. `"challenge.assumption_inversion"`, `"challenge.validation_gap"`)
- `plain_message`: the objection in one sentence
- `decision`: `"warn"` (never block automatically — the human decides)
- `extends_finding_id`: the finding this challenge responds to, if applicable
- `contradicts_finding_id`: any existing finding this objection overturns, if applicable

Do NOT record WEAK objections as findings. Include them only in the report.

### Step 6 — Output the report

```markdown
# Challenge Report

**Target:** [plan title or finding rule_id]
**Hypothesis:** [stated or inferred]
**Expected signal:** [stated or inferred, or "not specified"]

## Verdict: [BLOCK | ADDRESS BEFORE EXECUTION | PROCEED WITH CAVEATS]

## Strong objections
[list, or "None"]

## Moderate objections
[list, or "None"]

## Weak objections / notes
[list, or "None"]

## Findings recorded
[list of ck_finding IDs created, or "None"]
```

## Integration with ck_review_submit

After a challenge that clears (no STRONG objections), the caller can re-submit the plan with the moderate objections addressed. The new submission should include:
- `hypothesis`: the hypothesis now made explicit
- `expected_signal`: the observable confirmation criterion
- Prior challenge findings referenced in `alignment_context`

This creates a traceable chain: plan → challenge → revised plan → execution.

## What this skill does NOT do

- It does not rewrite or fix the plan. It challenges it.
- It does not block execution directly. It records findings and gives a recommendation.
- It does not repeat static policy checks (`ck_validate` covers those). It targets reasoning and assumption errors.
