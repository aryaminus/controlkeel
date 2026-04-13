# ControlKeel Alignment Checklist (Phoenix)

Use this checklist to keep agent/LLM work aligned, governed, and release-safe for this repository.

## Context

- Repo: (this repository)
- Stack: Phoenix 1.8 + Ecto + LiveView
- Governance runtime: ControlKeel
- Primary quality gate: `mix precommit`

## Owners And Defaults

- Workspace ID: `<WORKSPACE_ID>`
- Default policy set name: `phoenix-default-v1`
- Default agent target: `opencode`
- Findings approval owner: `<HUMAN_REVIEWER>`
- Budget owner: `<ENGINEERING_MANAGER>`

## 1) Bootstrap And Attach

Run from the governed project root:

```bash
controlkeel bootstrap
controlkeel init
controlkeel attach opencode
controlkeel status
```

Source-wrapper equivalent:

```bash
mix ck.init
mix ck.attach opencode
mix ck.status
```

Checks:

- `controlkeel/project.json` exists
- `controlkeel/bin/controlkeel-mcp` exists
- agent reports the `controlkeel` MCP is registered

## 2) Install Phoenix Default Policy Set

Create rules file:

- Path: `ops/policies/phoenix-default-v1.json`
- Rule format must match additive ControlKeel entries (`id`, `category`, `severity`, `action`, `plain_message`, `matcher`)

Suggested rule coverage:

- block deprecated LiveView navigation (`live_redirect`, `live_patch`)
- block HEEx direct changeset access (`@changeset[...]`, `<.form for={@changeset}>`)
- block unsafe inline script tags in HEEx
- block mass-assignment risk fields in `cast` (`user_id`, `account_id`, `workspace_id`)
- block unparameterized SQL patterns
- warn on raw HTML risks
- escalate to human when merge/release intent appears without quality gates

Create + apply:

```bash
controlkeel policy-set create \
  --name "phoenix-default-v1" \
  --scope workspace \
  --description "Phoenix + agent safety baseline" \
  --rules-file ops/policies/phoenix-default-v1.json

controlkeel policy-set list
controlkeel policy-set apply <WORKSPACE_ID> <POLICY_SET_ID> --precedence 100
```

## 3) Baseline Findings And Watch

```bash
controlkeel findings --severity high --status open
controlkeel watch --interval 2000
```

Rules:

- critical/high findings block release path
- no auto-approval; only human approves findings
- approval uses `controlkeel approve <FINDING_ID>` with rationale recorded in PR

## 4) Daily Agent Workflow

1. `controlkeel status`
2. Execute agent task
3. `controlkeel findings`
4. Resolve/approve findings as needed
5. `mix precommit`
6. `controlkeel proofs`
7. Attach proof id(s) to PR notes

Do not merge if any of these are true:

- open critical/high finding exists
- `mix precommit` fails
- no proof bundle for the task

## 5) Weekly Alignment Loop (Drift Correction)

```bash
controlkeel benchmark list --domain-pack software
controlkeel benchmark run --suite <SUITE_ID>
controlkeel benchmark show <RUN_ID>

controlkeel policy train --type router
controlkeel policy train --type budget_hint
controlkeel policy list
controlkeel policy show <POLICY_ID>
```

Promote only when:

- benchmark score improves vs current baseline
- no regression on safety scenarios
- budget profile is within target

Promotion command:

```bash
controlkeel policy promote <POLICY_ID>
```

## 6) Release Gate

Required before ship:

- `mix precommit` passes on release candidate commit
- `controlkeel findings --status open` has no high/critical items
- proof bundle exists for all release-blocking tasks
- promoted policies are documented in release notes

Recommended verification commands:

```bash
mix precommit
controlkeel status
controlkeel findings --status open
controlkeel proofs
```

## 7) Incident Response (If Drift Or Unsafe Output Appears)

1. Pause affected task flow
2. capture current findings and proof ids
3. freeze risky route/policy usage (do not promote new artifacts)
4. patch rules in `ops/policies/phoenix-default-v1.json`
5. rerun benchmark suite and compare with baseline
6. resume only after safety scenarios pass

## 8) PR Template Snippet (Optional)

Copy into PR descriptions:

```text
ControlKeel checks:
- Status checked: yes/no
- Findings reviewed: yes/no
- Open high/critical findings: 0
- mix precommit: pass/fail
- Proof bundle ids: <ID_1>, <ID_2>
- Policy set in effect: phoenix-default-v1
```

## 9) Quick Command Reference

```bash
controlkeel status
controlkeel findings
controlkeel approve <FINDING_ID>
controlkeel proofs
controlkeel proof <TASK_ID_OR_PROOF_ID>
controlkeel watch --interval 2000
controlkeel benchmark list
controlkeel benchmark run --suite <SUITE_ID>
controlkeel policy list
controlkeel policy train --type router
controlkeel policy train --type budget_hint
controlkeel policy promote <POLICY_ID>
```
