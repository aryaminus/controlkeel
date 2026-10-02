# API Reference

This is a code-aligned map of the stable HTTP surfaces in `ControlKeelWeb.Router`.
It is intentionally grouped by boundary instead of being a generated route dump; use
`mix phx.routes` when you need the full development-only route list.

## Human UI

Public entry points:

- `GET /` — home
- `GET /getting-started` — first-run guidance
- `GET /auth/login` — sign-in via configured OAuth providers (Google/GitHub); creates an account on first sign-in
- `GET /auth/logout` — logout
- `GET /auth/complete/:token` — auth completion
- `GET /cloud/invitations/:token` — invitation acceptance

Cloud-auth gated dashboard routes:

- `/dashboard`
- `/missions`, `/missions/start`, `/missions/:id`
- `/findings`
- `/proofs`, `/proofs/:id`
- `/reviews/:id`
- `/benchmarks`, `/benchmarks/runs/:id`
- `/cloud/telemetry`, `/cloud/projects`, `/cloud/projects/:ws_id`
- `/org/:slug/members`, `/org/:slug/settings/auth`, `/org/:slug/settings/general`
- `/workspaces/:id/repos`, `/workspaces/:id/service-accounts`, `/workspaces/:id/webhooks`, `/workspaces/:id/tool-policy`
- `/observability` and the observability subroutes for loop, costs, evals, imports, memory quality, recommendations, regressions, trends, promotions, sessions, and benchmark history/drafts/scenarios
- `/policies`, `/skills`, `/deploy`

## JSON API (`/api/v1`)

The JSON API backs local and hosted automation. The main resource groups are:

- Sessions and tasks: `/sessions`, `/sessions/:id`, `/sessions/:id/run`, `/sessions/:session_id/tasks`, `/tasks/:id/*`
- Reviews: `/reviews`, `/reviews/:id`, `/reviews/:id/respond`, `/review/diff`, `/review/pr`
- Governance: `/validate`, `/findings`, `/findings/:id/action`, `/release/readiness`, `/governance/install/github`
- Proof and memory: `/proofs`, `/proofs/:id`, `/proof/:task_id`, `/memory/search`, `/memory`, `/memory/:id`
- Benchmarks: `/benchmarks`, `/benchmarks/runs`, `/benchmarks/runs/:id`, `/benchmarks/runs/:id/import`, `/benchmarks/runs/:id/export`
- Budget and routing: `/budget`, `/route-agent`, `/agents`
- Context and improvement: `/context`, `/improvement`, `/sessions/:id/audit-log`, `/sessions/:id/graph`, `/sessions/:id/execute`
- Workspace operations: `/workspaces/:id/service-accounts`, `/workspaces/:id/policy-sets`, `/workspaces/:id/webhooks`, `/workspaces/:id/tool-policy`
- NHI lifecycle: `/service-accounts/:id/rotate`, `/service-accounts/:id`, `/service-accounts/:id/events`, `/webhooks/:id/replay`
- Providers: `/providers`, `/providers/status`, `/providers/default`
- Skills: `/skills`, `/skills/targets`, `/skills/export`, `/skills/install`, `/skills/:name`

## Protocol surfaces

Hosted protocol endpoints:

- `GET /.well-known/oauth-protected-resource/mcp`
- `GET /.well-known/oauth-protected-resource`
- `GET /.well-known/oauth-authorization-server`
- `GET /.well-known/agent-card.json`
- `GET /.well-known/agent.json`
- `POST /oauth/token`
- `GET /mcp`, `POST /mcp`, `DELETE /mcp`
- `POST /a2a`

Provider proxy endpoints:

- `POST /proxy/openai/:proxy_token/v1/responses`
- `POST /proxy/openai/:proxy_token/v1/chat/completions`
- `POST /proxy/openai/:proxy_token/v1/completions`
- `POST /proxy/openai/:proxy_token/v1/embeddings`
- `GET /proxy/openai/:proxy_token/v1/models`
- `GET /proxy/openai/:proxy_token/v1/realtime`
- `POST /proxy/anthropic/:proxy_token/v1/messages`
- `POST /proxy/gemini/:proxy_token/v1beta/chat/completions`
- `GET /proxy/gemini/:proxy_token/v1beta/openai/models`

## Cloud sync and runtime callbacks

Cloud/self-host sync endpoints:

- `POST /cloud/v1/telemetry`
- `POST /cloud/v1/runtime/callbacks`
- `POST /cloud/v1/workspaces/register`
- `POST /cloud/v1/sync/push`
- `POST /cloud/v1/sync/pull`
- `GET /cloud/v1/orgs/:slug/usage`

## Drift rule

If this file disagrees with `lib/controlkeel_web/router.ex`, the router wins. Update this
document in the same change that adds or removes a public route group.
