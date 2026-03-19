---
name: benchmark-operator
description: "Run, inspect, import, and export ControlKeel benchmark suites and multi-subject matrices. Use this when comparing governed and external agents or validating policy changes."
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
disable-model-invocation: true
metadata:
  author: controlkeel
  version: "2.0"
  category: benchmark
---

# Benchmark Operator Skill

Use this skill when the task is benchmark orchestration instead of normal governed delivery work.

## Workflow

1. Select the suite and subjects.
2. Run the suite or import manual outputs.
3. Review catch rate, block rate, expected-rule hit rate, latency, and overhead.
4. Export the run if you need external analysis.

## Additional resources

- [Benchmark operator playbook](references/benchmark-playbook.md)

