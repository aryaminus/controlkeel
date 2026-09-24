defmodule ControlKeelWeb.SessionObservabilityOverview do
  @moduledoc """
  Overview stage of the session observability page
  (`/:org_slug/workspaces/:ws_slug/sessions/:id/observability`).
  Migrated verbatim from the former `ObservabilityLive` page: run health,
  budget, findings, gates, hosts/models/tools, memory/proof links,
  recommendations, and trace/audit exports. Presentational only.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: ControlKeelWeb.Endpoint,
    router: ControlKeelWeb.Router,
    statics: ControlKeelWeb.static_paths()

  attr :run, :map, required: true
  attr :org_slug, :string, required: true
  attr :ws_slug, :string, required: true

  def overview_panel(assigns) do
    ~H"""
    <section
      id="observability-run-page"
      class="border rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
    >
      <div
        id="observability-costs"
        class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1"
      >
        <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Budget</p>
        <p class="text-2xl font-semibold">
          {@run.budget["decision"] || "unknown"}
        </p>
        <p class="text-muted-foreground text-xs">
          {format_currency(@run.budget["spent_cents"] || 0)} / {format_currency(
            @run.budget["session_budget_cents"] || 0
          )} used
        </p>
        <p class="text-muted-foreground text-xs">
          Rolling 24h: {format_currency(@run.budget["rolling_24h_spend_cents"] || 0)} / {format_currency(
            @run.budget["daily_budget_cents"] || 0
          )}
        </p>
      </div>

      <div
        id="observability-tools"
        class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-3"
      >
        <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
          Hosts, models, and tools
        </p>
        <div class="grid grid-cols-2 gap-3">
          <div class="space-y-1">
            <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
              Invocations
            </p>
            <p class="text-base font-semibold">
              {@run.hosts_models_tools.invocations}
            </p>
          </div>
          <div class="space-y-1">
            <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
              Estimated cost
            </p>
            <p class="text-base font-semibold">
              {format_currency(@run.hosts_models_tools.estimated_cost_cents)}
            </p>
          </div>
          <div class="space-y-1">
            <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
              Sources
            </p>
            <p class=" text-xs">
              {format_frequency(@run.hosts_models_tools.by_source)}
            </p>
          </div>
          <div class="space-y-1">
            <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
              Models
            </p>
            <p class=" text-xs">
              {format_frequency(@run.hosts_models_tools.by_model)}
            </p>
          </div>
          <div class="space-y-1">
            <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
              Tools
            </p>
            <p class=" text-xs">
              {format_frequency(@run.hosts_models_tools.by_tool)}
            </p>
          </div>
        </div>
      </div>

      <div
        id="observability-memory-proof"
        class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-2"
      >
        <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
          Context, memory, and proof
        </p>
        <div class="flex flex-wrap items-center gap-4 text-sm">
          <span class="text-muted-foreground">
            {@run.proofs.count} proof(s) · {@run.tasks.active}/{@run.tasks.total} tasks · {@run.memory.records} memory record(s)
          </span>
        </div>
      </div>

      <%= if @run.recommendations != [] do %>
        <div id="observability-recommendations" class="space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Recommendations
          </p>
          <ul class="list-disc pl-5">
            <%= for recommendation <- @run.recommendations do %>
              <li class="text-muted-foreground text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div id="observability-telemetry-export" class="flex justify-end">
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
      </div>

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
