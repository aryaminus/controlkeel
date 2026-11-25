---
name: security-review
description: "Run a structured security review before marking a task done. Services as the single audit skill for OWASP, baseline pack, domain-pack (HR/legal/marketing/sales/real-estate/government/insurance/logistics/manufacturing/e-commerce/nonprofit), and compliance (GDPR/SOC2/HIPAA/policy packs) — subsumes the deprecated `compliance-audit` and `domain-audit` aliases. Use this for code, config, architecture, or release reviews; the domain/compliance layer is triggered by the session's active domain pack and data flows."
when_to_use: "Use before merging, deploying, or signing off on code, config, or architecture changes (including regulated data flows, external integrations, exports, and any session whose domain pack is HR/legal/marketing/sales/real-estate/government/insurance/logistics/manufacturing/e-commerce/nonprofit). Activates for auth/input/secrets/deps and for domain/compliance coverage — the policy/domain-pack layer is driven by `ck_context`'s active compliance profile."
argument-hint: "[file, PR, area, or domain-pack scope to review]"
license: Apache-2.0
redirect_to: security-review
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
metadata:
  author: controlkeel
  version: "2.1"
  category: security
  subsumes:
    - compliance-audit
    - domain-audit
    - agent-pattern-verification
  ck_mcp_tools:
    - ck_validate
    - ck_context
    - ck_finding
    - ck_regression_result
  related_skills:
    - agent-pattern-verification
---

# Security Review Skill

Use this skill before closing a task, approving a proof bundle, or reviewing a risky diff.

## Three-Tier Boundary System

Apply this explicit boundary system during review:

### Always Do (No Exceptions)
- Validate all external input at system boundaries
- Parameterize all database queries
- Encode output to prevent injection
- Use HTTPS for external communication
- Hash passwords with strong algorithms
- Set security headers (CSP, HSTS, X-Frame-Options)
- Use httpOnly, secure, sameSite cookies for sessions
- Run dependency audits before releases

### Ask First (Requires Human Approval)
- Adding or changing authentication flows
- Storing new categories of sensitive data (PII, payment info)
- Adding new external service integrations
- Changing CORS configuration
- Adding file upload handlers
- Modifying rate limiting or throttling
- Granting elevated permissions or roles

### Never Do
- Never commit secrets to version control
- Never log sensitive data (passwords, tokens, full card numbers)
- Never trust client-side validation as a security boundary
- Never disable security headers for convenience
- Never use eval() or innerHTML with user-provided data
- Never store sessions in client-accessible storage
- Never expose stack traces or internal error details to users

## Review flow

1. Call `ck_context` to load the domain pack, risk tier, open findings, instruction hierarchy, and design-drift signals.
2. Check if agent frameworks are detected in workspace context. If agent frameworks (LangGraph, CrewAI, AutoGen, LangChain) are present, activate the agent-pattern-verification skill for additional agent-specific checks.
3. Run `ck_validate` on the relevant code or config slices, including trust-boundary metadata when the proposed action was influenced by web, tool, skill, or mixed-provenance content.
4. Apply the three-tier boundary system to classify each finding: always-do, ask-first, or never-do.
5. Walk the review checklist in [references/review-checklist.md](references/review-checklist.md).
6. Persist any missed issue with `ck_finding`, including boundary tier classification in metadata.
7. If external security or regression systems produce exploit or browser evidence, record that through `ck_regression_result` when it affects release readiness.
8. Summarize blockers, warnings, and follow-up proof requirements, grouped by boundary tier.

## Agent Pattern Integration

When agent frameworks are detected in the workspace context, this skill automatically includes agent-specific pattern checks:

- **Loop Safety**: Detects `while True` without break, recursive calls without depth limits
- **Retry Limits**: Validates retry decorators have explicit stop conditions
- **Tool Registry**: Cross-references tool definitions with prompt references
- **Context Size**: Monitors system prompt and tool description token counts
- **Graph Cycles**: Analyzes LangGraph graphs for unreachable END nodes

These checks complement the baseline security review with agent-specific anti-pattern detection.

## Additional resources

- For anti-rationalization patterns to help recognize and reject security shortcuts, see [references/anti-rationalization-patterns.md](references/anti-rationalization-patterns.md).
