defmodule ControlKeelWeb.SessionObservabilityLive do
  @moduledoc """
  Session observability page under the organization layout: one route
  (`/:org_slug/workspaces/:ws_slug/sessions/:id/observability`).
  Replaces the former tabbed `/observability/sessions/:id/*` family
  (see `docs/issues/session-observability-stacked-organization-route.md`).
  Timeline lives canonically in `SessionActivityLive` (`.../activity`).
  Renders inline `~H` (no separate stage components).

  CLI parity: overview section mirrors `controlkeel obs run <id>`
  (`Observability.session_run/1`); memory section mirrors
  `controlkeel obs memory <id>` (`Observability.memory_context/1`);
  envelope download mirrors `controlkeel obs export <id>`.
  Event signals summarize `controlkeel obs timeline <id>`
  (`Observability.timeline/1`) without duplicating the full
  `SessionActivityLive` event feed — only exact event-type/actor
  breakdowns and proof-linked events (which Activity does not surface).
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Observability
  alias ControlKeelWeb.SessionScope

  @impl true
  def mount(%{"id" => id, "org_slug" => org_slug, "ws_slug" => ws_slug}, _session, socket) do
    current_user = socket.assigns[:current_user]

    session = SessionScope.fetch_session(id)

    cond do
      is_nil(session) ->
        {:ok, SessionScope.session_not_found(socket)}

      not Accounts.session_accessible?(session, current_user) ->
        {:ok, SessionScope.session_not_found(socket)}

      SessionScope.check_scope(session, org_slug, ws_slug) != :ok ->
        {:ok, SessionScope.session_not_found(socket)}

      true ->
        # Reuse the already-fetched session struct: the `%Session{}`
        # overloads skip their own `get_session_context` reloads
        # (`ensure_preloaded`/`ensure_workspace_preloaded` passthrough),
        # so mount costs one full session load plus the aggregate/count
        # queries instead of four session loads.
        run = Observability.session_run(session)
        timeline = Observability.timeline(session, limit: 50)
        memory_context = Observability.memory_context(session, limit: 20)

        {:ok,
         socket
         |> assign(:page_title, "Observability — #{run.session.title}")
         |> assign(:org_slug, org_slug)
         |> assign(:ws_slug, ws_slug)
         |> assign(:run, run)
         |> assign(:timeline, timeline)
         |> assign(:memory_context, memory_context)
         |> assign_session_nav(session)}
    end
  end

  defp assign_session_nav(socket, session) do
    workspace = session.workspace
    org = workspace && workspace.org

    crumbs =
      if org && workspace do
        [
          %{label: org.name, to: "/#{org.slug}"},
          %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"},
          %{
            label: session.title,
            to: "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}"
          },
          %{label: "Observability", to: nil}
        ]
      else
        []
      end

    socket
    |> assign(:nav_org, org)
    |> assign(:nav_workspace, workspace)
    |> assign(:nav_session, %{id: session.id, title: session.title})
    |> assign(:breadcrumbs, crumbs)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="session-observability-page" class="w-full space-y-6">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="space-y-1">
          <.page_title
            title="Session observability"
            subtitle="How this session spent its budget, what the agent used, and what it remembers."
          />
          <p class="text-xs text-muted-foreground">
            Session: <span class="font-medium text-foreground">{@run.session.title}</span>
          </p>
        </div>
        <div id="observability-telemetry-export" class="shrink-0 space-y-2 sm:text-right">
          <.link
            href={
              ~p"/#{@org_slug}/workspaces/#{@ws_slug}/sessions/#{@run.session.id}/observability/export.json"
            }
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-primary-foreground shadow-sm transition hover:bg-primary/90"
          >
            Download JSON envelope
          </.link>
          <p class="text-xs text-muted-foreground">
            Machine-readable run envelope for export or re-import.
          </p>
        </div>
      </div>

      <section id="observability-run-page" class="space-y-4">
        <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <article
            id="observability-costs"
            class="rounded-2xl border bg-card p-5 shadow-card"
          >
            <.section_title>Spend</.section_title>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {format_currency(@run.budget["spent_cents"] || 0)} of {format_currency(
                @run.budget["session_budget_cents"] || 0
              )}
            </p>
            <p class="mt-1 text-xs text-muted-foreground">
              Budget decision: {@run.budget["decision"] || "unknown"} · Rolling 24h {format_currency(
                @run.budget["rolling_24h_spend_cents"] || 0
              )} of {format_currency(@run.budget["daily_budget_cents"] || 0)}
            </p>
          </article>

          <article
            id="observability-tools"
            class="rounded-2xl border bg-card p-5 shadow-card"
          >
            <.section_title>Agent usage</.section_title>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {@run.hosts_models_tools.invocations} calls · {format_currency(
                @run.hosts_models_tools.estimated_cost_cents
              )} est.
            </p>
            <dl class="mt-3 space-y-1.5 text-xs text-muted-foreground">
              <div class="flex gap-2">
                <dt class="w-16 shrink-0 font-medium">Sources</dt>
                <dd>{format_frequency(@run.hosts_models_tools.by_source)}</dd>
              </div>
              <div class="flex gap-2">
                <dt class="w-16 shrink-0 font-medium">Models</dt>
                <dd>{format_frequency(@run.hosts_models_tools.by_model)}</dd>
              </div>
              <div class="flex gap-2">
                <dt class="w-16 shrink-0 font-medium">Tools</dt>
                <dd>{format_frequency(@run.hosts_models_tools.by_tool)}</dd>
              </div>
            </dl>
          </article>

          <article
            id="observability-memory-proof"
            class="rounded-2xl border bg-card p-5 shadow-card"
          >
            <.section_title>Work captured</.section_title>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {@run.tasks.active}/{@run.tasks.total} tasks · {@run.proofs.count} proofs
            </p>
            <p class="mt-1 text-xs text-muted-foreground">
              {@run.memory.records} memory note(s) saved · details below
            </p>
          </article>
        </div>

        <%= if Enum.uniq(@run.recommendations ++ @memory_context.recommendations) != [] do %>
          <div
            id="observability-recommendations"
            class="rounded-2xl border bg-card p-5 shadow-card"
          >
            <.section_title>What to do next</.section_title>
            <ul class="mt-3 ml-5 list-disc space-y-1.5">
              <%= for recommendation <- Enum.uniq(@run.recommendations ++ @memory_context.recommendations) do %>
                <li class="text-sm leading-6 text-muted-foreground">{recommendation}</li>
              <% end %>
            </ul>
          </div>
        <% end %>
      </section>

      <section
        id="session-observability-timeline"
        class="rounded-2xl border bg-card p-5 shadow-card scroll-mt-6"
      >
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <.section_title>Event signals</.section_title>
            <p class="mt-1 text-sm text-muted-foreground">
              What happened, grouped by exact event and actor — the full feed with
              task/finding/review links lives in Activity.
            </p>
          </div>
          <span id="observability-timeline-total" class={neutral_pill_class()}>
            {@timeline.count} events
          </span>
        </div>

        <div id="observability-timeline-summary" class="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div class="rounded-xl bg-muted/[0.03] p-4">
            <p class="text-sm font-medium text-muted-foreground">Exact events</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {map_size(@timeline.by_event_type)} kinds
            </p>
            <p class="mt-1 text-xs text-muted-foreground">
              {format_frequency(@timeline.by_event_type)}
            </p>
          </div>
          <div class="rounded-xl bg-muted/[0.03] p-4">
            <p class="text-sm font-medium text-muted-foreground">Actors</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {map_size(@timeline.by_actor)} actors
            </p>
            <p class="mt-1 text-xs text-muted-foreground">
              {format_frequency(@timeline.by_actor)}
            </p>
          </div>
          <div class="rounded-xl bg-muted/[0.03] p-4">
            <p class="text-sm font-medium text-muted-foreground">Window</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {@timeline.count} of {@timeline.limit}
            </p>
            <p class="mt-1 text-xs text-muted-foreground">
              <.link
                navigate={
                  ~p"/#{@org_slug}/workspaces/#{@ws_slug}/sessions/#{@run.session.id}/activity"
                }
                class="font-medium text-primary transition hover:underline"
              >
                Open full event feed →
              </.link>
            </p>
          </div>
        </div>

        <%= if Enum.any?(@timeline.events, & &1.proof_id) do %>
          <div id="observability-timeline-proofs" class="mt-5 space-y-3">
            <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Events with proof bundles
            </p>
            <ul class="divide-y divide-border list-none p-0 m-0 border-y">
              <%= for event <- Enum.take(Enum.filter(@timeline.events, & &1.proof_id), 3) do %>
                <li class="flex flex-wrap items-center justify-between gap-2 px-4 py-3">
                  <div class="min-w-0">
                    <p class="text-sm font-medium text-foreground">{event.summary}</p>
                    <p class="text-xs text-muted-foreground">
                      {event.event_type} · {event.actor}
                    </p>
                  </div>
                  <.link
                    navigate={~p"/proofs/#{event.proof_id}"}
                    class="text-xs font-semibold text-primary transition hover:underline"
                  >
                    Proof #{event.proof_id} →
                  </.link>
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
      </section>

      <section
        id="session-observability-memory"
        class="rounded-2xl border bg-card p-5 shadow-card scroll-mt-6"
      >
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <.section_title>What the agent remembers</.section_title>
            <p class="mt-1 text-sm text-muted-foreground">
              Notes saved during {@memory_context.session.title} — what was kept and where it came from.
            </p>
          </div>
          <span id="observability-memory-total" class={neutral_pill_class()}>
            {@memory_context.memory.active} active
          </span>
        </div>

        <div id="observability-memory-summary" class="mt-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
          <div class="rounded-xl bg-muted/[0.03] p-4">
            <p class="text-sm font-medium text-muted-foreground">Kept notes</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {@memory_context.memory.active} active
            </p>
            <p class="mt-1 text-xs text-muted-foreground">
              {@memory_context.memory.archived} archived · {@memory_context.memory.count} recent
            </p>
          </div>
          <div class="rounded-xl bg-muted/[0.03] p-4">
            <p class="text-sm font-medium text-muted-foreground">Session context</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {@memory_context.context.tasks} tasks
            </p>
            <p class="mt-1 text-xs text-muted-foreground">
              {@memory_context.context.findings} findings · {@memory_context.context.reviews} reviews
            </p>
          </div>
          <div class="rounded-xl bg-muted/[0.03] p-4">
            <p class="text-sm font-medium text-muted-foreground">Note types</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {map_size(@memory_context.memory.by_type)} kinds
            </p>
            <p class="mt-1 text-xs text-muted-foreground">
              {format_frequency(@memory_context.memory.by_type)}
            </p>
          </div>
          <div class="rounded-xl bg-muted/[0.03] p-4">
            <p class="text-sm font-medium text-muted-foreground">Saved by</p>
            <p class="mt-1 text-lg font-semibold text-foreground/90">
              {map_size(@memory_context.memory.by_source)} sources
            </p>
            <p class="mt-1 text-xs text-muted-foreground">
              {format_frequency(@memory_context.memory.by_source)}
            </p>
          </div>
        </div>

        <div id="observability-memory-records" class="mt-5 space-y-3">
          <div class="flex items-center justify-between gap-4">
            <.section_title>Recent notes</.section_title>
            <.link
              navigate={~p"/observability/memory-quality"}
              class="text-sm font-medium text-primary transition hover:underline"
            >
              Memory quality →
            </.link>
          </div>
          <%= if @memory_context.memory.recent == [] do %>
            <p class="text-sm text-muted-foreground">
              Nothing saved yet — notes the agent keeps during this session will show up here.
            </p>
          <% else %>
            <ul class="divide-y divide-border list-none p-0 m-0 border-y">
              <%= for record <- @memory_context.memory.recent do %>
                <li id={"observability-memory-record-#{record.id}"} class="px-4 py-3 space-y-1">
                  <div class="flex items-center justify-between gap-4">
                    <div>
                      <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                        {record.record_type}
                      </p>
                      <p class="text-sm font-semibold text-foreground">{record.title}</p>
                    </div>
                    <span class={neutral_pill_class()}>
                      {if record.archived, do: "archived", else: "active"}
                    </span>
                  </div>
                  <p class="text-sm leading-6 text-muted-foreground">{record.summary}</p>
                  <p class="text-xs text-muted-foreground">
                    Source: {record.source_type || "unknown"} · Tags: {Enum.join(record.tags, ", ")}
                  </p>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </section>
    </section>
    """
  end

  defp format_currency(cents) when is_integer(cents), do: (cents / 100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
