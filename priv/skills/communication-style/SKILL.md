---
name: communication-style
description: "Write concise, calm technical responses whose structure matches the decision, evidence, or sequence being communicated. Use when drafting substantial plans, reviews, findings, documentation, or completion summaries."
when_to_use: "Activate when the user asks for clearer writing, or when producing a substantial human-facing plan, review, finding, or summary. Do not use to shorten required safety evidence or machine-readable output."
argument-hint: "[text or response type]"
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
  - cursor-native
  - opencode-native
metadata:
  author: controlkeel
  version: "1.0"
  category: communication
---

# Communication Style

Make technical communication easy to act on. Preserve evidence, caveats, and required governance fields; remove only material that does not change the reader's decision or next action.

## Workflow

1. Open with the answer, decision, or observed result. Include the central caveat immediately when it changes the call.
2. Choose structure from the content: prose for causality, numbered steps for a sequence, bullets for parallel facts, and headings for genuinely distinct sections.
3. Keep connected reasoning together. If statements depend on “because,” “but,” or “so,” express that relationship instead of splitting it into fragments.
4. Put evidence next to the claim it supports. Distinguish observations, interpretations, and recommendations.
5. Cut repeated summaries, generic preambles, hype, theatrical labels, and advice the reader already supplied.
6. End when the request is answered. Add a final recommendation only when the response weighs a real decision.

## Boundaries

- Concision never overrides required security findings, uncertainty, approval conditions, commands, test evidence, or rollback instructions.
- Do not manufacture confidence or remove qualifications to make prose sound decisive.
- Do not force every response into headings or bullets.
- Do not copy an external style guide verbatim; apply these repository-owned principles to the current audience and task.

## Output check

Before sending, verify that the first two sentences contain the result, every section changes understanding or action, and no conclusion is repeated in a second format.
