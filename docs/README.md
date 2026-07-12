# ControlKeel Documentation

ControlKeel is the control plane for AI-agent work: policy gates, findings, proofs, budgets, evals, and durable context across the tools your team already uses. Start with the job you need done, not with the feature list.

## Start and prove value

- [getting-started.md](getting-started.md): install, attach one agent host, reach the first governed finding, and create proof you can show a teammate or buyer
- [benchmarks.md](benchmarks.md): built-in suites, with-vs-without CK comparison, false-positive disclosure, latency/token fields when measured, and bounded claim wording
- [cost-governance.md](cost-governance.md): token, rate-limit, subscription-window, and budget-control guidance

## Connect the tools people already use

- [agent-integrations.md](agent-integrations.md): how ControlKeel works across agent hosts, MCP, runtime export, and protocol interop
- [support-matrix.md](support-matrix.md): code-aligned inventory of hosts, transport modes, exports, and protocol tools
- [packages.md](packages.md): package catalog and when to use each distribution surface
- [code-mode-governance.md](code-mode-governance.md): progressive discovery, generated scripts, and runtime guardrails

## Govern work, not just prompts

- [autonomy-and-findings.md](autonomy-and-findings.md): findings, approvals, autonomy posture, hook enforcement, typed memory lifecycle, and intent-based human gates
- [agent-specs.md](agent-specs.md): reusable agent/task behavior contracts for specs, reviews, and benchmarks
- [observability-feedback-loop.md](observability-feedback-loop.md): local eval-to-draft-to-benchmark-to-promotion-advisory workflow with regression evidence
- [control-plane-claim-matrix.md](control-plane-claim-matrix.md): README claim-to-test matrix for governance, memory, cloud sync, and human gates
- [testing/evidence.md](testing/evidence.md): application performance baselines, profiling evidence, and the reviewed boundary for future browser/visual tests
- [testing/harness-tools.md](testing/harness-tools.md): commit-linked performance comparison, generated test inventory audits, and bounded BEAM profiling plans

## Operate teams, projects, and cloud deployments

- [self-hosting.md](self-hosting.md): self-hosted deployment guidance
- [hosting/](hosting/): hosting-related documentation
- [api-reference.md](api-reference.md): code-aligned HTTP routes for sessions, reviews, findings, proofs, benchmarks, service accounts, webhooks, policy sets, hosted protocols, and cloud telemetry
- [cli-reference.md](cli-reference.md): command topics, common commands, and pointer to live `controlkeel help`
- [adrs/](adrs/): Architecture Decision Records for major technical decisions
