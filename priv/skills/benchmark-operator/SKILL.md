---
name: benchmark-operator
description: "Run, inspect, import, and export ControlKeel benchmark suites and multi-subject matrices. Use this when comparing governed and external agents or validating policy changes."
when_to_use: "Activate when the user asks to benchmark, compare, or validate agent behavior, or when running regression tests after policy changes."
argument-hint: "[benchmark suite name or agent to compare]"
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
  - cline-native
  - cursor-native
  - windsurf-native
  - continue-native
  - letta-code-native
  - pi-native
  - roo-native
  - goose-native
  - opencode-native
  - antigravity-cli-native
  - kiro-native
  - kilo-native
  - amp-native
  - augment-native
  - devin-terminal-native
  - warp-native
  - droid-bundle
disable-model-invocation: true
metadata:
  author: controlkeel
  version: "2.0"
  category: benchmark
  ck_mcp_tools:
    - ck_observability
---

# Benchmark Operator Skill

Use this skill when the task is benchmark orchestration instead of normal governed delivery work.

## Workflow

1. Select the suite and subjects.
2. Run the suite or import manual outputs.
3. Review catch rate, block rate, expected-rule hit rate, latency, and overhead.
4. Export the run if you need external analysis.

## Local observability feedback loop

For generated observability coverage, prefer the human-gated loop:

1. Inspect `ck_observability` reports for `saved_evals`, `benchmark_drafts`, `benchmark_scenarios`, and `benchmark_history`.
2. Use CLI-only commands for mutations: draft approval, materialization, and benchmark execution are not exposed through MCP in this skill.
3. Run generated observability benchmarks only after a dry-run review and explicit operator approval.
4. Treat `promotions` as advisory evidence; do not mutate policy, router, prompt, or autofix artifacts from benchmark results alone.

## Additional resources

- [Benchmark operator playbook](references/benchmark-playbook.md)

