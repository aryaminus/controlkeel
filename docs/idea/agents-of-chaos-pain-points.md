# Agents of Chaos: Pain Point Analysis for ControlKeel

Reference paper: Agents of Chaos (arXiv:2602.20021v1, 2026-02-23)

## Executive Summary

The paper reports 11 concrete autonomous-agent failure patterns in persistent, multi-channel environments.
The core takeaway is that model-level safety alone is not enough once agents can execute tools, retain memory,
and interact through untrusted channels.

This document maps those failure patterns to ControlKeel's agent ecosystem and current mitigations.

## Consolidated Case Categories

| # | Category | Typical Impact |
| --- | --- | --- |
| 1 | Unauthorized compliance | Agent obeys non-owner instructions |
| 2 | Semantic reframing | Sensitive action is reworded and bypasses intent checks |
| 3 | Identity hijack | Spoofed sender or actor gains trust |
| 4 | System sabotage | Destructive infrastructure or filesystem action |
| 5 | External file corruption | Malicious external config controls agent behavior |
| 6 | Denial of service loops | Infinite reasoning/tool loops and degraded availability |
| 7 | Resource overconsumption | Cost and runtime blowups |
| 8 | Task hallucination | Agent reports success without verifiable completion |
| 9 | Cross-agent propagation | Unsafe behavior spreads across cooperating agents |
| 10 | Social coherence failure | Agent loses coherent identity/context model |
| 11 | Partial system takeover | Unauthorized privilege gain or admin control |

## ControlKeel Agent Surface

### Execution modes

| Mode | What it means |
| --- | --- |
| Direct | ControlKeel launches local/CLI agent workflows directly |
| Handoff | ControlKeel prepares packages for external IDE/client execution |
| Runtime | ControlKeel delegates to remote or headless cloud runtimes |
| Inbound-only | Agent can call into ControlKeel but is not fully driven by it |

### Representative integrations by mode

| Mode | Integrations |
| --- | --- |
| Direct | Claude Code, Codex CLI, Gemini CLI, OpenCode, Aider |
| Handoff | Cursor, Windsurf, Copilot/VS Code, Kiro, Amp, Roo Code, Cline, Continue, Goose, Hermes Agent, OpenClaw, Droid |
| Runtime | Devin, Open SWE, Forge |
| Inbound-only | Framework adapters, provider profiles, research/unverified adapters |

## Risk Mapping by Agent Category

### 1) Local coding agents (direct)

Primary risks:

1. Unauthorized compliance from prompt-injected project content.
2. Destructive shell/file actions.
3. Task hallucination and incomplete verification.
4. Secret disclosure through tool output or model prompts.

Current mitigations:

1. Pre-commit policy checks.
2. Scanner-based policy validation and secret detection.
3. Circuit breaker patterns for high-risk execution.
4. Outcome tracking for completion evidence.

Residual risk level: high

### 2) IDE-integrated agents (handoff)

Primary risks:

1. Scope-escaping file mutations.
2. Cross-agent propagation of unsafe edits.
3. Task completion claims without proof.
4. Sensitive context leakage from workspace files.

Current mitigations:

1. Validation on staged/generated content.
2. Pattern-based risk detection for generated changes.
3. Outcome tracker and review gates.
4. Session-bound governance context.

Residual risk level: medium to high

### 3) Cloud runtime agents (runtime)

Primary risks:

1. Cost runaway from autonomous loops.
2. Prompt injection via external sources (issues, PRs, URLs).
3. Infrastructure-changing operations with broad permissions.
4. Privilege creep and partial takeover behaviors.

Current mitigations:

1. Budget thresholds and spend alerts.
2. Circuit breakers and governance gates.
3. Policy scanning before execution-critical transitions.
4. Findings and proof-based release checks.

Residual risk level: high to critical

### 4) Specialized/mobile/inbound agents

Primary risks:

1. Sensitive device-data handling (contacts, media, location).
2. Identity spoofing in communication channels.
3. Low-observability side effects.

Current mitigations:

1. Limited-scope integration defaults.
2. Session tracking and governance guidance.
3. Recommendation to enforce proxy/runtime controls where native hooks are limited.

Residual risk level: medium to high

## Social Coherence Failures

The paper highlights social coherence failures as a separate class from classic hallucination.
In practice this includes inconsistent identity, contradictory state reports, and unstable instruction precedence.

ControlKeel-relevant manifestations:

1. Agent claims task complete while evidence disagrees.
2. Agent follows mutually conflicting principals.
3. Agent output contradicts observed scanner findings.

Current controls:

1. Outcome proof tracking.
2. Session-bound governance state.
3. Findings translation for human review.

Remaining need:

1. Explicit instruction-precedence tracking.
2. Stronger identity provenance across channels.

## Coverage Matrix

| Vulnerability class | Existing control | Main gap | Priority |
| --- | --- | --- | --- |
| Unauthorized compliance | Scanner plus policy gates | Better untrusted-external-content validation | P1 |
| Destructive actions | Circuit breaker plus scanner checks | Stronger boundary-aware file/system policy | P1 |
| Sensitive disclosure | PII/secret detection and proxy scanning | Broader output scanning coverage | P1 |
| Resource overconsumption | Budget alerts and cost controls | Earlier pre-flight budget denial rules | P1 |
| Task hallucination | Outcome tracking | Strong proof-of-success requirements | P1 |
| Cross-agent propagation | Pattern memory and scanner | Explicit inter-agent trust boundaries | P2 |
| Identity hijack | Session monitoring | Hardened actor identity validation | P2 |
| System sabotage | Circuit breaker | Blast-radius enforcement improvements | P2 |
| Semantic reframing | Pattern scanning | Context-aware dataflow semantics | P2 |
| External file corruption | Pre-commit checks | Supply-chain integrity verification | P2 |
| Social coherence failures | Session/governance context | Instruction precedence model | P3 |
| DoS loops | Budget and circuit controls | Tool-level loop/rate controls | P3 |
| Partial takeover | Circuit breaker and review gates | Privilege-escalation behavior detection | P3 |

## Recommended Next Closures

1. External content validator for issues, PRs, and fetched URLs before task execution.
2. Proof-of-success verifier that parses evidence from tests, deploy checks, and health signals.
3. Context-aware dataflow checks to catch semantic reframing paths.
4. Output scanning for agent-generated code, commit text, and PR descriptions.
5. Supply-chain integrity checks for package and script trust.
6. Privilege-escalation detection with explicit governance findings.

## Practical Conclusion

ControlKeel already addresses many high-value controls highlighted by the paper, especially around scanner,
budget, and governance-layer interventions. The largest remaining risks are external-content trust, proof quality,
and stronger identity/coherence guarantees in multi-agent and runtime-heavy workflows.
