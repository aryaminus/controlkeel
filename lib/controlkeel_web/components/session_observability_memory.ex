defmodule ControlKeelWeb.SessionObservabilityMemory do
  @moduledoc """
  Memory stage of the session observability page
  (`/:org_slug/workspaces/:ws_slug/sessions/:id/observability`).
  Migrated verbatim from the former `ObservabilityMemoryLive` page.
  Presentational only.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: ControlKeelWeb.Endpoint,
    router: ControlKeelWeb.Router,
    statics: ControlKeelWeb.static_paths()

  attr :memory_context, :map, required: true

  def memory_panel(assigns) do
    ~H"""
    <section
      id="session-observability-memory"
      class="border rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5 scroll-mt-6"
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <h2 class="text-xl font-semibold text-primary">Context and memory</h2>
          <p class="text-muted-foreground text-sm mt-1">
            Summary-only memory and context posture for {@memory_context.session.title}.
          </p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <span id="observability-memory-total" class={neutral_pill_class()}>
            {@memory_context.memory.active} active memory
          </span>
        </div>
      </div>

      <div id="observability-memory-summary" class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Memory</p>
          <p class="text-2xl font-semibold">
            {@memory_context.memory.active} active
          </p>
          <p class="text-muted-foreground text-xs">
            {@memory_context.memory.archived} archived / {@memory_context.memory.count} recent
          </p>
        </div>
        <div class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Context</p>
          <p class="text-2xl font-semibold">
            {@memory_context.context.tasks} task(s)
          </p>
          <p class="text-muted-foreground text-xs">
            {@memory_context.context.findings} finding(s), {@memory_context.context.reviews} review(s)
          </p>
        </div>
        <div class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Types</p>
          <p class="text-2xl font-semibold">
            {map_size(@memory_context.memory.by_type)}
          </p>
          <p class="text-muted-foreground text-xs">
            {format_frequency(@memory_context.memory.by_type)}
          </p>
        </div>
        <div class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Sources</p>
          <p class="text-2xl font-semibold">
            {map_size(@memory_context.memory.by_source)}
          </p>
          <p class="text-muted-foreground text-xs">
            {format_frequency(@memory_context.memory.by_source)}
          </p>
        </div>
      </div>

      <%= if @memory_context.recommendations != [] do %>
        <div id="observability-memory-recommendations" class="space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Recommended next actions
          </p>
          <ul class="list-disc pl-5">
            <%= for recommendation <- @memory_context.recommendations do %>
              <li class="text-muted-foreground text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div id="observability-memory-records" class="space-y-3">
        <div class="flex items-center justify-between gap-4">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Recent memory records
          </p>
          <.link
            navigate={~p"/observability/memory-quality"}
            class="text-sm text-primary font-semibold hover:opacity-80 transition-opacity"
          >
            Memory quality →
          </.link>
        </div>
        <div class="space-y-3 max-h-[550px] overflow-y-auto pr-1">
          <%= if @memory_context.memory.recent == [] do %>
            <p class="text-muted-foreground text-sm">
              No memory records are available for this session.
            </p>
          <% else %>
            <%= for record <- @memory_context.memory.recent do %>
              <div
                id={"observability-memory-record-#{record.id}"}
                class="rounded-xl px-4 py-3 border bg-[rgba(255,255,255,0.015)] space-y-1"
              >
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                      {record.record_type}
                    </p>
                    <p class="text-sm font-semibold">{record.title}</p>
                  </div>
                  <span class={neutral_pill_class()}>
                    {if record.archived, do: "archived", else: "active"}
                  </span>
                </div>
                <p class="text-sm leading-relaxed">{record.summary}</p>
                <p class="text-muted-foreground text-xs">
                  Source: {record.source_type || "unknown"} · Tags: {Enum.join(record.tags, ", ")}
                </p>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp neutral_pill_class do
    "inline-flex items-center border rounded-full px-3 py-1.5 text-sm bg-muted text-muted-foreground"
  end

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
