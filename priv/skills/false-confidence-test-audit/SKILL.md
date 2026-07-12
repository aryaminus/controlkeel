---
name: false-confidence-test-audit
description: "Audit tests that may pass without proving the claimed behavior. Use for periodic test-quality reviews or when coverage looks healthy but regressions still escape."
when_to_use: "Activate only when the user requests a test-quality, false-confidence, or assertion-strength audit. Do not rewrite tests until each weakness is reproduced or supported by concrete evidence."
argument-hint: "[test path, suite, or commit range]"
disable-model-invocation: true
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
  - cursor-native
  - opencode-native
result-schema:
  type: object
  required: [scope, findings, commands_run, limitations]
  properties:
    scope: {type: string}
    findings:
      type: array
      items:
        type: object
        required: [path, claim, evidence, severity, recommended_probe]
        properties:
          path: {type: string}
          claim: {type: string}
          evidence: {type: string}
          severity: {type: string, enum: [high, medium, low]}
          recommended_probe: {type: string}
    commands_run: {type: array, items: {type: string}}
    limitations: {type: array, items: {type: string}}
metadata:
  author: controlkeel
  version: "1.0"
  category: quality
  ck_mcp_tools: [ck_context, ck_validate, ck_finding, ck_regression_result]
---

# False-Confidence Test Audit

Find tests whose green result overstates what they prove. This is an evidence audit, not a request to maximize coverage or replace outcome tests with implementation checks.

## Workflow

1. State the suite's claimed behavior and identify the production boundary that should make the claim observable.
2. Run the narrow test unchanged and record its command and result.
3. Inspect for assertions that cannot fail, status-only assertions, permissive schemas, broad truthiness checks, over-mocked boundaries, implementation mirroring, skipped CI lanes, missing negative cases, and fixtures that bypass the behavior under test.
4. For each suspected weakness, propose the smallest probe that would make the test fail if the production behavior were broken. Prefer a temporary mutation, boundary substitution, or explicit counterexample when safe.
5. Separate confirmed weaknesses from hypotheses. Record limitations when a probe cannot be run.
6. Fix only confirmed weaknesses, then demonstrate that the strengthened test fails against the broken behavior and passes against the correct behavior.

## Boundaries

- Never weaken production behavior to make a test easier to write.
- Do not delete a test merely because it overlaps another; identify the distinct claim first.
- Do not introduce sleeps, network dependence, random timing, or broad HTML snapshots as substitutes for behavioral evidence.
- Full mutation testing is optional and must be budgeted separately.

## Completion

Return output matching the declared result schema. A clean audit states what was inspected and which claims were actually challenged; “no findings” without commands and limitations is incomplete.
