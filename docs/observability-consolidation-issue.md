## Summary

The workspace now has 12 observability pages (Benchmark, Observability overview, Learning loop, Memory quality, Trends, Problems, Recommendations, Evals, Costs, Imports, Compare, Promotions) that repeat each other's sections, data queries, and actions. This issue proposes merging the overlaps and removing pages that don't earn their place by user utility — fewer pages, each with one clear job — plus a punch-list of fixes carried over from the workspace-scope migration reviews.

## Motivation

A user asking "is my workspace healthy and what do I do next?" currently has to tour 4–5 pages that say overlapping things. Section inventory (from the live templates) shows a `Recommendations`/`Recommended next actions` block on 8 of the 12 pages (benchmark, compare, costs, evals, imports, loop ×2, memory quality, problems, promotions, trends — only the overview titles its variant differently, and it has one too). Health rollups appear on overview, loop, and evals. The same invocation aggregates power both Compare and Costs. Problems derive Eval candidates which become Benchmark drafts which become Promotions — one pipeline split across four pages with four framings. Each page also re-runs shared aggregates: `loop_status` recomputes `workspace_overview` plus `recommendations`, and `perf_snapshot` runs overview + loop + recommendations + costs again. Users pay this as duplicated reading and duplicated loading.

## Current state (evidence)

Page sections today (`lib/controlkeel_web/live/observability_*_live.ex`):

- Overview: runs / problems / costs / trace-export cards, recommended actions, top problems, recent sessions.
- Learning loop: safety boundary, problems/evals/benchmarks/promotions stat cards, blockers, next actions, recommendations, loop diagnostics, perf snapshot.
- Compare: invocations/spend/tokens, group comparisons, recommendations.
- Costs: cost suggestions, agent comparison, recommendations, group breakdown.
- Evals: recommended actions, active + saved candidates.
- Imports: recommendations, recent imports.
- Memory quality: distribution, recommendations, stale/duplicate/contradiction/missed-memory sections.
- Recommendations: active recommendations (a page that is only the repeated block).
- Trends: recommendations, daily series.
- Problems: recommendations, feedback loop, examples.
- Promotions: recommendations, candidates.
- Benchmark: drafts, tests, run history, regressions, recommendations.

Data-function overlaps (`lib/controlkeel/observability.ex`): `workspace_overview` recomputed by `loop_status` and `recommendations`; `comparison` vs `costs` over the same invocations; `problems` → `eval_candidates` → benchmark drafts → `promotion_candidates` as one pipeline in four costumes; `memory_quality` vs the session page's memory section; imports vs the overview trace-export card.

Cross-scope duplicates: session observability repeats run/cost/memory proof blocks available at workspace scope; `candidate.links.benchmarks` points at global `/benchmarks` while the workspace page is `/.../benchmark`; the session page links the legacy export URL although org-scoped export routes exist (`router.ex`).

## Candidate merges (proposal — needs a utility decision per item, not a decree)

- Fold Loop into Overview: loop's stat cards, blockers, and next actions are an overview with stricter framing. Keep diagnostics + perf snapshot as sections of the merged page or drop the snapshot button (it duplicates `obs` CLI timing and writes a memory record per click).
- Fold Compare into Costs: one cost page with a grouping control instead of two pages over the same invocations.
- Fold Recommendations away entirely: every page already carries its own recommendations block; the standalone page adds nothing. Delete it and keep the blocks.
- Fold Evals into Benchmark (draft pipeline) or into Problems (derivation source): candidates are a transient state between problem groups and benchmark drafts, not a destination page. Merge and cross-link instead.
- Fold Imports into Overview trace-export: imports is one card + one list; it fits as an overview section with a link to full history only if usage warrants it.
- Keep with a sharpened job: Problems (group triage), Trends (time view), Memory quality (memory ops), Promotions (human gate), Benchmark (exam loop) — but strip each page's repeated recommendations/health blocks in favor of links.
- Delete candidates: the standalone Recommendations page first; then whichever of Compare/Imports loses its merge decision.

## Other suggested fixes (carried over)

- Costs crash: `suggestion.savings_percent` dot-access 500s when the hygiene suggestion fires; atom/string key mismatch silences local-model/batching suggestions and breaks priority pills (`cost_optimizer.ex`, `observability_costs_live.ex`).
- Loop snapshot flash claims "captured and persisted" without checking the persist result; `save-candidates` rescue covers only `RuntimeError`.
- `workspace_link_base` runs even when zero links are emitted; `loop_status`/`perf_snapshot` recompute shared aggregates — resolve lazily or thread slugs from the already-fetched overview.
- Tests: tighten overview link assertions to full workspace prefixes; add unauthorized cross-workspace patch test; live tests for compare/costs/imports/memory/recommendations/problems/promotions.
- Benchmark inconsistency (for PR #204, not here): own `WorkspaceScope` copies, `admin`-for-reads vs `viewer` elsewhere, legacy export link on the session page.

## Acceptance criteria

- Each surviving page has one documented job; no `Recommendations`-titled block appears on more than the pages that own recommendations.
- Removed pages 302 to their merge target (same resolver pattern as the workspace migration), never 404.
- Shared aggregates computed once per page load; no page recomputes `workspace_overview` when it already holds it.
- `mix precommit` clean.

## Implementation slices (in order; each mergeable)

1. Decide per page: keep (with job statement), merge (with target), or delete — one line each in this issue before code.
2. Delete the standalone Recommendations page + strip repeated recommendation/health blocks to links (no data changes).
3. Merge Compare into Costs (grouping control) with redirect.
4. Merge Evals into the agreed target with redirects + cross-links.
5. Fold Loop into Overview (or justify keeping it) with redirect; resolve the snapshot button fate.
6. Fix list (costs crash, snapshot flash, link laziness) + tests + precommit.

Branch: new branch off `feat/observability-workspace-scope` per slice (e.g. `feat/observability-consolidation`).

## Test plan

- Targeted first: per-slice live tests (merged page renders both contents; removed paths 302 to targets with query preserved).
- Regression: existing workspace-scope suites stay green (45+ tests).
- Full: `mix precommit`.

## Risks / notes

- Every merge needs its redirect registered before the `:org_slug` catch-all; single-segment paths must stay ahead of the browser scope (lesson from the `/observability` shadowing bug).
- Deleting a page users bookmarked is a UX break even with redirects — announce removals, keep redirects permanently.
- Do not merge Benchmark in this issue; it belongs to PR #204's scope and gates `admin`.

## References

- Migration: issue #202, PR #204.
- Routes: `lib/controlkeel_web/router.ex` (workspace `observability/*`, `PageController.observability_page_redirect`).
- Shared scope: `lib/controlkeel_web/live/workspace_scope.ex`.
- Style: `docs/ui-style-guide.md`.
