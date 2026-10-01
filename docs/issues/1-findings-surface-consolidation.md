# Findings render on three surfaces; drop the workspace problems page and keep session findings + global triage

Fix order: **first** — this is a small, self-contained fix that `docs/issues/issue-reminder.md` builds on.

## Summary

Findings data renders on three web surfaces reading the same `findings` table. The workspace `/observability/problems` page is the weakest of the three: read-only, a synonym name for findings, and its aggregate information is already fully available elsewhere. Drop it and make session findings the primary instance surface.

## Current behavior

| Surface                      | Scope         | Granularity                                                                                                                      |
| ---------------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `.../sessions/:id/findings`  | one session   | individual findings, full disposition: approve/reject/escalate, fixes, 2s live refresh (`session_findings_live.ex:107-200`)      |
| `/findings`                  | all sessions  | individual findings + filters + triage rulings; flat, time-ordered — session is a filter, not the root (`mission.ex:6603-6620`)  |
| `.../observability/problems` | one workspace | aggregate: `GROUP BY rule_id/category` with counts, examples (`observability.ex:131-153`); zero `handle_event` — fully read-only |

The problems page adds nothing the other surfaces need:

- Instance examples → session findings shows them better, live.
- The aggregate → `Observability.eval_candidates/1` maps **every** problem group (not a subset) into candidates carrying `rule_id`, `finding_count`, `affected_session_count`, evidence, benchmark hint, and example session links (`observability.ex:851-856,3149-3171`). The eval candidates list is the complete per-rule aggregate one stage upstream.
- Overview already renders a "Top problems" section and stat card without the dedicated page.

`Observability.problems/1` itself must stay — it feeds `eval_candidates/1`, `workspace_overview/1`, `loop_status/1`, CLI `obs problems`, and the MCP `problems` report.

## Expected behavior

- Findings instances: session findings (primary, in-context) and `/findings` (cross-session triage).
- Recurrence aggregate: visible in web through eval candidates (loop) and overview "Top problems" — all groups, not a top-N cap, with example session deep links.
- No workspace problems route, no "problems" synonym for findings.
- Context function, CLI, and MCP unchanged.

## Proposed change

1. Delete the problems route, LiveView, and nav entry. The workspace URL 404s through the catch-all — findings are already surfaced on the overview (`#problems`), session findings, and `/findings`, so no workspace redirect is warranted.
2. Legacy-global `/observability/problems` keeps resolving: rewrite the suffix to the overview root with the `#problems` anchor (single hop, no chain) via the existing redirect (`router.ex:190`).
3. Retarget the six dependents on the problems URL:
   - nav entry — `organization_layouts.ex:714`
   - workspace route — `router.ex:246`
   - legacy redirect — `router.ex:190`
   - overview "Review groups" link — `observability_overview_live.ex:117`
   - context-generated link literals — `observability.ex:3046` (`add_problem_actions`) and `observability.ex:3166` (eval candidate `links.problems`)
4. While touching `observability.ex:3166-3169`, fix the pre-existing legacy URL shape `/observability/sessions/#{id}` to org-scoped routes.
5. Overview keeps only the problems stat card (group count + active findings count); per-group detail is not re-rendered — the loop page's eval candidates remain the per-rule surface.
6. Migrate problems LiveView tests to the surviving surfaces.

## Acceptance criteria

- [ ] Workspace `/observability/problems` 404s (route removed); legacy-global shape 302s to the workspace overview.
- [ ] No remaining references to the problems URL in `lib/` or `test/` — the six dependents retargeted or removed.
- [ ] Context-generated links use org-scoped routes (no `/observability/sessions/:id` literals).
- [ ] Overview problems stat shows true counts: distinct `(rule_id, category)` group count and total active findings, not capped by the aggregate query limit; per-group detail lives in the loop's eval candidates.
- [ ] `Observability.problems/1`, CLI `obs problems`, and the MCP `problems` report unchanged.
- [ ] `mix precommit` green; problems LiveView tests migrated.
