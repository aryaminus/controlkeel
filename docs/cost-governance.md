# Cost, token, and rate-limit governance

ControlKeel treats model usage as a governed resource, not an unlimited side effect of agent work. The goal is to avoid burning through subscription windows, API budgets, and context windows while still letting agents work.

## What CK can enforce directly

- **Session budget**: `ck_budget` and proxy preflight block work that would exceed the session cap.
- **Rolling 24-hour budget**: CK tracks invocation spend over the last 24 hours and warns/blocks near configured limits.
- **Proxy token estimates**: provider proxy requests are estimated from request text plus requested max output, then committed from provider usage when available.
- **Cached-token accounting**: invocation records include cached input tokens so cost and cache behavior remain visible.
- **Compact context**: `ck_context` defaults to compact output; request full context only when raw workspace/resume/transcript payloads are required.
- **Circuit breakers**: agent monitors can trip on API-call rate, file-modification rate, error rate, consecutive failures, and budget-burn rate.
- **Provider trust/routing**: provider status distinguishes CK-owned providers, host-managed bridges, local Ollama, and heuristic fallback.

## What providers and hosts still own

CK cannot reliably know every user subscription quota for Claude Code, Codex, Cursor, Copilot, Cline, Roo, Continue, or other host-owned plans. These products often use rolling windows, weekly caps, premium-request pools, token multipliers, or auto-model fallbacks that are not exposed through a stable local API.

For BYOK/API paths, provider dashboards remain the hard source of truth:

- Anthropic exposes spend limits, RPM, input-token-per-minute, output-token-per-minute, retry-after, and `anthropic-ratelimit-*` headers. Prompt caching can reduce billed and rate-limited input tokens for repeated context.
- OpenAI exposes RPM, RPD, TPM, TPD, IPM, usage tiers, long-context limits, retry-after, and `x-ratelimit-*` headers. Keep `max_tokens` close to the expected answer size because oversized caps can affect rate-limit accounting.
- Hosted coding tools such as Cursor, Copilot, Claude Code, and Codex may layer their own subscription windows or credit systems over provider limits. Treat their warnings as authoritative.

## Operating checklist

Before expensive or parallel work:

1. Run `ck_budget` with an estimate and stop if it warns or blocks.
2. Prefer compact `ck_context`; use `detail_level: full` only for targeted recovery.
3. Split work into small vertical slices; avoid unbounded AFK loops.
4. Use cheaper/auto/local models for routine search, formatting, and first-pass review.
5. Cap output tokens to the expected response size.
6. Avoid launching parallel agents unless the DAG shows independent unblocked tasks and budget headroom.
7. Watch provider/host quota warnings; if a 429 occurs, respect `retry-after` instead of looping.
8. Configure hard spend caps in provider dashboards for BYOK/API usage.

## Proxy observability

When CK proxies provider traffic, it preserves allowlisted rate-limit metadata in invocation records:

- `retry-after`
- OpenAI-style `x-ratelimit-*`
- Anthropic-style `anthropic-ratelimit-*`

This metadata helps diagnose whether a failure was session budget pressure, provider RPM/TPM pressure, output-token pressure, or a host-owned subscription window. CK intentionally does not persist arbitrary response headers because headers can contain sensitive or noisy data.

## Known limitation

CK currently records provider rate-limit telemetry but does not run a full account-specific token-bucket scheduler. Active throttling needs provider/account limit discovery and host subscription APIs where available. Until then, CK blocks on its own budgets, records provider headers, and surfaces operator guidance.
