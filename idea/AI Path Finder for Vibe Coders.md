# Legacy Pathfinder Note

This document is no longer a roadmap. The older Pathfinder report was useful because it argued for a missing control plane above code generators, but most of that core product thesis is now shipped in ControlKeel.

## What was worth keeping

- generators are abundant, directors are missing
- the hard part is not code generation, it is governed delivery
- agent output needs a production-engineering layer around it
- non-experts need plain-language guidance, visible constraints, and evidence, not just faster syntax generation

## What ControlKeel already ships

- control-tower positioning and governed-delivery framing
- occupation-first onboarding and domain-pack selection
- execution briefs, task planning, routing, validation, findings, and proof bundles
- typed memory, resume packets, and evidence surfaces
- Ship Dashboard and Benchmarks as proof-of-value surfaces
- typed integrations, MCP runtime, governed proxy, runtime export, provider brokerage, and fallback governance

## What the old report wanted that is intentionally not claimed here

- Pathfinder naming or branding
- autonomous hosting, deployment, or scale-to-zero control
- microVM / Firecracker / gVisor sandboxing
- self-healing, RL, or simulation-driven autopilot
- compliance guarantees such as SOC2-ready or HIPAA-ready infrastructure
- native support for every external generator

## Current ControlKeel reading of that report

The lasting value in the Pathfinder material is the product explanation:

- ControlKeel sits above generators.
- It turns agent output into production engineering.
- It is useful both for first-run governed delivery and for rescuing repos touched by unsupported tools.

For the current architecture map, use [docs/control-plane-architecture.md](../docs/control-plane-architecture.md). For current remaining work, use the remaining-roadmap docs instead of this note.
