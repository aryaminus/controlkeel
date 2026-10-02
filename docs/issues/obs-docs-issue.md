## Summary

The 12 workspace observability LiveViews each render a `CommandPill` naming the CLI command the page mirrors. This leaks an implementation detail into the product UI and belongs in documentation instead. Proposed: add a `/docs/observability` guide (theory, CLI reference, page↔command map), remove the pills from the LiveViews, and migrate the static guide prose currently living in those pages.

## Current behavior

Every observability page under `/:org_slug/workspaces/:ws_slug/observability/*` renders one or more `CommandPill`s:

| Page            | Pill rendered                                                                           |
| --------------- | --------------------------------------------------------------------------------------- |
| Overview        | `controlkeel obs`                                                                       |
| Loop            | `controlkeel obs loop`                                                                  |
| Costs           | `controlkeel obs costs`                                                                 |
| Trends          | `controlkeel obs trends`                                                                |
| Compare         | `controlkeel obs compare`                                                               |
| Evals           | `controlkeel obs evals`                                                                 |
| Imports         | `controlkeel obs imports`                                                               |
| Memory quality  | `controlkeel obs memory-quality`                                                        |
| Recommendations | `controlkeel obs recommend`                                                             |
| Promotions      | `controlkeel obs promotions`                                                            |
| Benchmark       | `controlkeel obs benchmarks drafts` / `scenarios` / `history` / `regressions` (4 pills) |

A workspace user viewing spend trends does not need to know the page parallels `controlkeel obs trends`. The mapping is useful knowledge, but it is developer-facing scaffolding, not operational UI.

Several pages also carry static teaching prose:

- `observability_benchmark_live.ex:366` — "Benchmark execution is CLI-only. Review generated scenarios first, then run an explicit command." plus per-tab execution-policy notes
- `observability_evals_live.ex` — "Advisory regression candidates derived from grouped problems and feedback evidence." and similar derivation explanations
- `observability_loop_live.ex` — learning-loop mode explanations, blocker/next-action guidance
- `observability_memory_quality_live.ex` — duplicate-cluster and staleness methodology notes

## Proposed solution

1. **Add `/docs/observability`** (one `DocsController` action, template, route, sidebar entry — the docs foundation from the docs-consolidation branch). Content:
   - **What observability is** — the evidence loop: sessions produce telemetry → telemetry aggregates into costs/trends → anomalies become eval candidates → evals feed benchmarks → benchmark outcomes drive promotions and memory writes; where a human enters the loop and why
   - **CLI reference** — the full `controlkeel obs …` surface including `--execute` gating for benchmarks, copyable (docs copy handler already exists)
   - **Page map** — which workspace page shows what, with workspace-scoped URL shapes and the page↔command mapping table
2. **Remove `CommandPill` from all observability LiveViews.** Pages keep their one-line subtitle and gain a "How this works →" link to the relevant `/docs/observability#section` anchor.
3. **Move static guide prose** from the LiveViews into the docs page, leaving LiveViews with data, actions, and single-line context.

## Engineering assessment

Agreed — this is the right factoring. Notes:

1. **The pills are UI debt.** Each costs an `on_mount` hook, a `handle_event` round-trip, and a flash to copy a string the end user was never supposed to need. Removing them simplifies 12 LiveViews; the CLI parallel remains true, it just stops being the UI's problem.
2. **Relocate the mapping, don't delete it.** A single maintained table on `/docs/observability` beats 13 scattered pills: one source, searchable, linkable — still serving terminal-first users and agents.
3. **Keep the markdown twin derived from the HTML page.** Docs-consolidation removed a hand-written Observability markdown section that had drifted from its page. That content is the natural seed here; derive or version both surfaces from one source so the drift cannot recur.
4. **Separation of concerns:** LiveViews keep data + actions; docs keep teaching. A future "needs a pill again" moment is the signal that content belongs in docs.
5. **Blast radius:**
   - `CommandPill` may become unused — retire it in the same PR or document remaining users (check non-observability usages first)
   - Update observability LiveView tests that assert pill markup
   - `ck_observability` MCP tool consumers are unaffected (agents get the CLI surface from the tool, not the pages)
   - Deep links need stable section ids (`#benchmarks`, `#costs`, …)

**Sequencing:** two PRs —
(a) add `/docs/observability` with the full guide (useful even with pills still present);
(b) remove pills, move static prose, add anchor links.
Each diff stays reviewable and (b) shrinks the LiveViews without content loss.

## Acceptance criteria

- [ ] `/docs/observability` renders theory, CLI reference (copyable), page↔command mapping, and web page map
- [ ] Sidebar, breadcrumb, sitemap, and markdown negotiation entries for the new route
- [ ] No `CommandPill` usage remains in observability LiveViews
- [ ] Static guide prose moved out of `observability_*_live.ex`; pages link to relevant doc anchors
- [ ] `CommandPill` retired or remaining users documented
- [ ] `DocsControllerTest` covers the new route; observability LiveView tests updated
- [ ] `mix precommit` clean

## Strict rule:

The cli functionality and feature and commands  and their output should remain unchanged. This issue is only converned with the web/ui presentation and features.