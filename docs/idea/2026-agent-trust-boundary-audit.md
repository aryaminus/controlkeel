# 2026 Agent Trust-Boundary Audit

This note captures the latest paper review behind the April 6, 2026 ControlKeel patch
that adds trust-boundary aware validation and explicit instruction hierarchy guidance.

## What the latest papers say

### 1. Instruction hierarchy matters, but only if privilege survives the full pipeline

- `Stronger Enforcement of Instruction Hierarchy via Augmented Intermediate Representations` (arXiv:2505.18907)
- Main takeaway:
  model-level instruction hierarchy is directionally correct, but the core insight for CK is simpler:
  instruction privilege must be carried explicitly, not inferred from raw text alone.
- Product implication for CK:
  the control plane should accept source privilege and intended use as first-class validation inputs.

### 2. External tool output should not be allowed to accumulate as authority

- `AgentSys: Secure and Dynamic LLM Agents Through Explicit Hierarchical Memory Management` (arXiv:2602.07398)
- Main takeaway:
  isolating tool outputs and only allowing schema-validated returns across boundaries sharply reduces
  indirect prompt-injection success.
- Product implication for CK:
  repo text, issue bodies, PR content, web fetches, skills, and tool outputs should default to data/context,
  not authority.

### 3. Causal takeover can happen across turns, not only inside one suspicious string

- `AgentSentry: Mitigating Indirect Prompt Injection in LLM Agents via Temporal Causal Diagnostics and Context Purification` (arXiv:2602.22724)
- Main takeaway:
  tool-return boundaries are the right checkpoint for deciding whether context is steering the agent away
  from trusted intent.
- Product implication for CK:
  high-impact actions should be gated when they are justified by mixed or untrusted context, even if the
  content is not obviously malicious.

### 4. Skills are now a supply-chain surface, not just a convenience surface

- `Skill-Inject: Measuring Agent Vulnerability to Skill File Attacks` (arXiv:2602.20156)
- Main takeaway:
  third-party skills can silently hijack agent behavior, and the benchmark shows high attack success rates.
- Product implication for CK:
  imported skills need provenance-aware handling and should not automatically gain execution authority.

### 5. Iteration does not reliably improve safety

- `Security Degradation in Iterative AI Code Generation -- A Systematic Analysis of the Paradox` (arXiv:2506.11022)
- Main takeaway:
  repeated "improvement" loops can make code less secure, not more secure.
- Product implication for CK:
  governance checks need to keep firing during iteration, and the validator should not assume that a later
  pass is safer than an earlier one.

## Critique of the papers from a product viewpoint

- The strongest papers focus on model architecture or benchmark settings, not deployable control-plane
  contracts. CK still needs lightweight production primitives that work across many hosts.
- AgentSys-style isolation is directionally correct, but CK is not the host runtime for every supported
  agent. Full memory isolation is a roadmap item, not an immediate patch.
- AgentSentry-style causal re-execution is promising, but it is heavier than what CK can honestly claim
  today in repo-local MCP flows.
- Skill-Inject is directly actionable because CK already treats skills as a product surface.

## What changed in ControlKeel

This patch adds a small but real upgrade:

1. `ck_validate` now accepts trust-boundary metadata:
   - `source_type`
   - `trust_level`
   - `intended_use`
   - `requested_capabilities`
2. Trust-boundary findings are produced when:
   - mixed or untrusted content is treated as instructions
   - an untrusted skill attempts to shape execution behavior
   - high-impact capabilities are requested from mixed or untrusted context
3. `ck_context` now returns an explicit instruction hierarchy so attached agents can see:
   - trusted sources
   - mixed-trust sources
   - untrusted sources
   - the gating rule for high-impact actions

## Why this is the right patch now

- It is immediately useful across CK's current MCP surface.
- It matches the strongest recurring research signal: source privilege and action authority need to be explicit.
- It is honest about current product shape: CK can govern boundaries now without pretending to implement full
  runtime isolation or causal replay for every host.

## Next research-backed upgrades

1. Tool-return quarantine:
   only schema-validated summaries from web/tool calls should flow back into the main agent context.
2. Review-time provenance for skills:
   expose approval/provenance state for installed skills and third-party bundles.
3. Counterfactual review replay:
   when a risky action is proposed, compare the action with and without the suspect external context.
4. Proof-of-success hardening:
   strengthen completion gating so "task done" claims require evidence from tests, deploy checks, or proofs.
