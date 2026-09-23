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
  attr :audit_exports, :list, required: true
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
          <a
            href="#session-observability-memory"
            class="text-xs text-primary font-semibold hover:opacity-80 transition-opacity"
          >
            Jump to memory →
          </a>
          <.link
            navigate={~p"/proofs?#{%{"session_id" => @run.session.id}}"}
            class="text-xs text-primary font-semibold hover:opacity-80 transition-opacity"
          >
            Open proofs →
          </.link>
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

      <div
        id="observability-telemetry-export"
        class="rounded-xl px-4 py-3 border bg-[rgba(255,255,255,0.015)] space-y-2"
      >
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Trace/proof export
        </p>
        <p class="text-muted-foreground text-sm leading-relaxed">
          Download the local observability envelope for this run, then preview it locally with <code class="text-primary font-semibold ml-2 text-xs">
              controlkeel obs import &lt;file&gt; --dry-run
            </code>.
        </p>
        <.link
          href={
            ~p"/#{@org_slug}/workspaces/#{@ws_slug}/sessions/#{@run.session.id}/observability/export.json"
          }
          class="text-sm text-primary font-semibold hover:opacity-80 transition-opacity"
        >
          Download JSON envelope →
        </.link>
      </div>

      <div
        id="observability-audit-log-export"
        class="rounded-xl px-4 py-3 border bg-[rgba(255,255,255,0.015)] space-y-2"
      >
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Audit log export
        </p>
        <p class="text-muted-foreground text-sm leading-relaxed">
          Checksummed audit artifact of record for this session, proofs embedded. The same export
          behind <code class="text-primary font-semibold ml-1 text-xs">controlkeel audit-log</code>.
        </p>
        <div class="flex flex-wrap items-center gap-2">
          <.link
            :for={format <- ~w(json csv pdf)}
            id={"observability-audit-export-#{format}"}
            href={
              ~p"/#{@org_slug}/workspaces/#{@ws_slug}/sessions/#{@run.session.id}/observability/audit-log/#{format}"
            }
            class="rounded-lg px-3 py-1.5 text-xs font-semibold uppercase tracking-[0.14em] border bg-muted/[0.03] text-muted-foreground hover:bg-muted/[0.08] hover:text-foreground transition"
          >
            {String.upcase(format)}
          </.link>
        </div>
        <%= if @audit_exports == [] do %>
          <p class="text-muted-foreground text-xs">
            No audit exports recorded yet — download one above, then reload to see its checksum here.
          </p>
        <% else %>
          <ul class="space-y-1 list-none p-0 m-0">
            <%= for export <- @audit_exports do %>
              <li class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                <span class="font-semibold uppercase">{export.format}</span>
                <code class="font-mono break-all">{export.checksum}</code>
                <span>{format_exported_at(export.generated_at)}</span>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>
    </section>
    """
  end

  defp format_currency(cents) when is_integer(cents), do: (cents / 100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0

  defp format_exported_at(nil), do: "unknown time"

  defp format_exported_at(%DateTime{} = at),
    do: Calendar.strftime(at, "%Y-%m-%d %H:%M:%S UTC")

  defp format_exported_at(%NaiveDateTime{} = at),
    do: Calendar.strftime(at, "%Y-%m-%d %H:%M:%S UTC")

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
