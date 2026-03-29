# ControlKeel Control-Plane Architecture

This document explains the current product architecture.

ControlKeel is not the code generator. It is the control plane above generators: the layer that turns agent output into governed, reviewable, production-minded delivery.

## The control-plane map

The older strategy split the product into seven pillars. In current ControlKeel terms, those map like this:

- **Harness**: typed integrations, attach flows, runtime export, provider broker, and project bootstrap
- **Tools**: MCP runtime, skills, generated plugin bundles, and governed proxy endpoints
- **Context**: execution brief, typed memory, proof bundles, resume packets, and current mission state
- **Orchestration**: planner, task graph, router, Mission Control, and agent recommendations
- **Invocation**: provider resolution, budget checks, governed forwarding, and no-key fallback behavior
- **Validation**: FastPath, Semgrep, optional advisory review, findings, and guided auto-fix
- **Evidence**: Proof Browser, Ship Dashboard, and Benchmarks

## What this means in product terms

The live governed lifecycle is:

1. intent intake
2. execution brief compilation
3. task graph and routing
4. validation and findings
5. proof capture
6. ship metrics
7. comparative benchmark evidence

That is why the main surfaces stay grouped as:

- Mission Control
- Proof Browser
- Ship Dashboard
- Benchmarks

## Project rescue and unsupported tools

ControlKeel does not need a fictional universal watcher or a native integration for every generator to be useful.

When another tool already changed the repo, the current rescue path is:

1. bootstrap the governed project
2. use `controlkeel watch` for live findings and budget state
3. use `controlkeel findings`, proofs, and `ck_validate` to assess the result
4. use governed proxy only when the tool can target compatible OpenAI- or Anthropic-style endpoints

That keeps the support story honest: some tools have first-class attach flows, some work through proxy or runtime export, and unsupported tools still participate in the governance loop after bootstrap.

## Not shipped by design

These ideas appeared in older planning documents, but they are not current product claims:

- no autonomous deployment engine
- no microVM or Firecracker / gVisor sandbox layer
- no RL / self-healing orchestration system
- no repo-native PR governor branch
- no team/platform or infrastructure completion in this doc; those remain deferred roadmap work

## Related docs

- [Getting started](getting-started.md)
- [Agent integrations](agent-integrations.md)
- [Support matrix](support-matrix.md)
- [Benchmarks](benchmarks.md)
- [Autonomy and findings](autonomy-and-findings.md)
