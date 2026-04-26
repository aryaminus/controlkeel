# Documentation Guide

This directory now has a simpler split:

- user-facing entry docs
- canonical reference docs
- maintainer and release docs
- internal planning docs

Use this page to decide where to read next.

## Start here

- [explaining-controlkeel.md](explaining-controlkeel.md): the plain-English "what CK is, why it exists, how it works, and what makes it different" explainer
- [how-controlkeel-works.md](how-controlkeel-works.md): the detailed implementation-level walkthrough of CK's control loop, runtime model, validation path, and evidence model
- [defensive-security-with-controlkeel.md](defensive-security-with-controlkeel.md): the defense-first security workflow guide covering cyber access modes, disclosure defaults, and benchmark interpretation
- [getting-started.md](getting-started.md): first install, first attach, provider setup, and hosted protocol basics
- [direct-host-installs.md](direct-host-installs.md): package, plugin, skills.sh, VSIX, and attach-first host install paths
- [support-matrix.md](support-matrix.md): canonical code-aligned inventory of hosts, transport modes, exports, and protocol tools

## Product and behavior reference

- [qa-validation-guide.md](qa-validation-guide.md): end-to-end QA playbook for validating the full product surface
- [agent-integrations.md](agent-integrations.md): how ControlKeel models integrations, bidirectional execution, and protocol interop
- [autonomy-and-findings.md](autonomy-and-findings.md): how findings, review state, and human approval interact
- [benchmarks.md](benchmarks.md): benchmark and evaluation surfaces
- [control-plane-architecture.md](control-plane-architecture.md): higher-level architecture map
- [code-mode-governance.md](code-mode-governance.md): progressive discovery, generated scripts, and code-mode runtime guardrails
- [cost-governance.md](cost-governance.md): token, rate-limit, subscription-window, and budget-control guidance
- [explaining-controlkeel.md](explaining-controlkeel.md): includes the explicit harness principles around context ownership, observability, extensibility, and provider portability

## Maintainer and release docs

- [host-surface-parity.md](host-surface-parity.md): host-surface rollout rationale and parity mapping
- [integration-validation-checklist.md](integration-validation-checklist.md): validation checklist for shipped integrations
- [release-verification.md](release-verification.md): release and publish verification steps
- [agent-support-prd.md](agent-support-prd.md): product intent behind the support catalog
- [agent-support-requirements.md](agent-support-requirements.md): support requirements and acceptance criteria

## Internal planning

The `docs/idea/` directory contains working product and research notes. Those files are useful for maintainers, but they are not the primary user docs and should not be treated as the shipped support contract.
