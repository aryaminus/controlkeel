This is a Phoenix web application governed by ControlKeel.

## ControlKeel Governance

Before shell, code, config, deploy, or broad cleanup work:

1. Call `ck_context` for mission, budget, findings, proof, workspace, and resume state.
2. Invoke the `controlkeel-governance` skill.
3. Call `ck_budget` before expensive, multi-phase, or delegated work.
4. Call `ck_validate` before shell commands, file writes, generated code, config changes, or deploy actions.
5. Use `ck_review_submit` and wait for `ck_review_status` approval before broad mutations or risky deletion.
6. Record durable decisions with `ck_memory_record`.
7. Record discovered issues with `ck_finding`.
8. Use `ck_route` before delegation.

Fresh sessions must reacquire CK state even if a conversation summary exists. If MCP is unavailable, manually check risk, findings, budget, and security implications before changing files, then leave clear session notes.

Keep this root file lean: only project-specific governance, commands, and critical gotchas belong here. Put reusable agent guidance in skills or focused docs.

## Issue and PR Quality

- Use evidence-based issue reporting: command run, expected behavior, actual behavior, exact error/log
- Avoid over-confident root cause analysis without supporting evidence
- When reviewing AI-generated contributions, use `ck_validate` with `source_type: "issue"` or `source_type: "pull_request"`
- Prefer invariant enforcement over local workarounds for bad states
- Use `deslop` skill to clean AI-generated issue/PR text slop

## Planning and Architecture

- Use structural planning: types/interfaces + call stacks + boundaries over prose descriptions
- Include call graphs to show what's allowed to talk to what (boundary enforcement)
- Apply targeted review loops (revise specific sections, don't rewrite everything)
- Let models correct their own mistakes using validation tools in agentic loops

## Project Commands

- Run `mix precommit` after code changes and fix pending issues.
- Use `Req` for HTTP; avoid `:httpoison`, `:tesla`, and `:httpc`.
- Use `apply_patch` for manual edits when available. Do not use shell writes for file edits.
- Read `mix help <task>` before unfamiliar Mix tasks.
- Prefer targeted tests first: `mix test test/path/to_test.exs` or `mix test --failed`.
- Avoid `mix deps.clean --all` unless there is a specific dependency corruption reason.

## Phoenix v1.8

- All layouts are **framework layouts** owned by `ControlKeelWeb.Layouts` (`components/layouts.ex`, `embed_templates "layouts/*"`): `:root`, `:public`, `:dashboard`. Organization pages use `ControlKeelWeb.OrganizationLayouts`. LiveView/controller templates render only their content; the framework wraps them — do NOT add per-page layout wrappers. Observability section routes use the `:dashboard` layout; session observability is stacked at `/:org_slug/workspaces/:ws_slug/sessions/:id/observability` under the organization layout.
- Set the layout per `live_session` (`layout: {ControlKeelWeb.Layouts, :dashboard}`) or per controller (`plug :put_layout, html: {ControlKeelWeb.Layouts, :public}`). The root layout is set via `put_root_layout` in the browser pipeline.
- Framework layouts share the page's render context, so `@flash`, `@current_user`, `@current_membership`, and `@inner_content` are available with **no forwarding**. `@current_path` (subnav/tab highlighting) is set by the `ControlKeelWeb.LayoutDefaults` `on_mount` hook.
- Reusable chrome (`<.sidebar>`, `<.flash_group>`) lives as function components in the `Layouts` module. `<.flash_group>` belongs there, called by the framework layouts.
- See `docs/framework-layout-migration.md` for the migration rationale.
- Use `<.icon name="hero-x-mark" class="w-5 h-5"/>`; do not call Heroicons modules directly.
- Use imported `<.input>` for form inputs. If overriding `class`, fully style the input because defaults are not inherited.
- Router scopes already include aliases; do not add duplicate route aliases.
- Do not use `Phoenix.View`.

## Elixir and Ecto

- Use `Enum.at/2` for list index access.
- Rebind block results outside the block.
- Do not nest multiple modules in one file.
- Access struct fields with `struct.field`, not map syntax.
- Use stdlib `Time`, `Date`, and `DateTime`; only use extra parsing deps already in the project.
- Never use `String.to_atom/1` on user input.
- Predicate functions end in `?`; reserve `is_` names for guards.
- Name OTP child specs, for example `{DynamicSupervisor, name: MyApp.Sup}`.
- Use `Task.async_stream/3` with back-pressure for concurrent enumeration.
- Preload associations used in templates.
- Use `:string` for schema text fields.
- `validate_number/2` has no `:allow_nil` option.
- Use `Ecto.Changeset.get_field/2` for changeset fields.
- Set programmatic fields like `user_id` explicitly, not through `cast`.
- Create migrations with `mix ecto.gen.migration descriptive_name`.

## HEEx and LiveView

- Use `~H` and `.html.heex`, never `~E`.
- Use `Phoenix.Component.form/1`, `inputs_for/1`, and `to_form/2`; do not use `Phoenix.HTML.form_for` or `<.form let={f}>`.
- Give every form a unique DOM id.
- Import app-wide helpers through the `html_helpers` block.
- Use `cond` or `case`; Elixir has no `else if`.
- Use `phx-no-curly-interpolation` for literal braces in `<code>` and `<pre>`.
- Use list syntax for class attrs and wrap inline `if` expressions.
- Use `<%= for %>` for template loops, not `Enum.each`.
- Use `<%!-- comment --%>` for HEEx comments.
- Use `{...}` for attributes and values; use `<%= %>` only for block constructs in tag bodies.
- Prefer `<.link navigate={href}>` and `<.link patch={href}>` over deprecated LiveView redirects.
- Avoid LiveComponents unless they solve a real boundary.
- Name LiveViews with a `Live` suffix.

## Streams, Hooks, and Tests

- Use LiveView streams for collections. Set `phx-update="stream"`, consume `@streams.name`, and use `reset: true` for filtering.
- Streams are not enumerable; refetch and re-stream instead of filtering in memory.
- Track counts and empty states in separate assigns.
- Re-stream items when assigns affecting streamed content change.
- Do not use deprecated `phx-update="append"` or `prepend`.
- Use `phx-update="ignore"` when a hook owns its DOM, and always provide a unique hook id.
- Prefer colocated hooks for template-local JS; keep ad hoc JavaScript out of HEEx templates.
- Use `push_event/3` for server-to-client events and rebind the socket.
- Use `Phoenix.LiveViewTest` and LazyHTML assertions. Test outcomes and selectors, not raw HTML blobs.
- In tests, use `start_supervised!/1`. Avoid `Process.sleep/1` and `Process.alive?/1`; use monitors or `_ = :sys.get_state(pid)` for synchronization.

## JS, CSS, and UI

- Follow `docs/ui-style-guide.md` for page titles, headings, cards, stat cards, tables, and tone tokens.
- Tailwind v4 import syntax in `app.css` must stay:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- Do not use `@apply` in raw CSS. The only exception is `@layer base` element resets on bare selectors (`*`, `html`, `body`) for theme tokens (e.g. `border-border`, `bg-background`, `font-sans`) — the documented Tailwind idiom. Never use `@apply` to hand-roll component or utility classes; build those as real Tailwind components instead.
- Build custom Tailwind components; do not add daisyUI.
- Only `app.js` and `app.css` bundles are supported. Import vendor deps there; do not reference external scripts/styles from layouts.
- Keep UI polished, responsive, accessible, and restrained. Use subtle transitions, clean spacing, and balanced typography.

<!-- controlkeel:start -->
# ControlKeel Companion Instructions

This project is governed by ControlKeel. Prefer the ControlKeel MCP server for validation, findings, budgets, proof context, workspace snapshots, transcript state, and routing.

Project root: this repository (your IDE workspace / `CK_PROJECT_ROOT`)
Target: `opencode`
Primary CK loop: `ck_context -> ck_validate -> ck_review_submit/ck_finding -> ck_budget/ck_route/ck_delegate`

Required workflow:
1. Call `ck_context` at the start of a task for mission, workspace, transcript, and resume context.
2. Call `ck_validate` before writing code, config, shell, or deploy content.
3. Submit plans or approval packets with `ck_review_submit` and check `ck_review_status` before execution.
4. Record any human-review issue with `ck_finding`.
5. Check `ck_budget` before expensive model or multi-agent work, and keep `ck_context` compact unless full raw context is needed.
6. Before AFK or delegated implementation, split large work into human-approved vertical slices with explicit dependencies; prefer durable behavior-first issues, stable deep-module interfaces, and branch-level automated review plus human QA before merge.
7. Use `ck_route`, `ck_skill_list`, and `ck_skill_load` to delegate or activate specialized CK workflows.

Install ControlKeel:
- Homebrew: `brew tap aryaminus/controlkeel && brew install controlkeel`
- npm bootstrap: `npm i -g @aryaminus/controlkeel`
- Unix installer: `curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh`
- Raw GitHub shell installer: `curl -fsSL https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.sh | sh`
- PowerShell installer: `irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex`
- Raw GitHub PowerShell installer: `irm https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.ps1 | iex`
- GitHub Releases: `https://github.com/aryaminus/controlkeel/releases`

ControlKeel auto-bootstraps project binding on first use. Provider access resolves through agent bridge, CK-owned provider profiles, local Ollama, then heuristic fallback.
<!-- controlkeel:end -->
