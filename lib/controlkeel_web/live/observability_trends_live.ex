defmodule ControlKeelWeb.ObservabilityTrendsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability
  alias ControlKeelWeb.WorkspaceScope

  @impl true
  def mount(params, _session, socket) do
    case WorkspaceScope.assign_scope(socket, params, "Trends") do
      {:ok, socket} ->
        {:ok, socket |> assign(:page_title, "Observability trends") |> assign_workspace_opts()}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  defp assign_workspace_opts(socket) do
    %{workspace: workspace} = socket.assigns

    socket
    |> assign(:opts, workspace_id: workspace.id)
    |> assign(:org_slug, workspace.org.slug)
    |> assign(:ws_slug, workspace.slug)
  end

  @impl true
  def handle_params(params, _url, %{assigns: %{workspace_scope: _}} = socket) do
    case WorkspaceScope.refresh(socket, params) do
      {:ok, socket, _changed?} ->
        {:noreply, socket |> assign_workspace_opts() |> load_trends(parse_days(params["days"]))}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select_days", %{"days" => days}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/#{socket.assigns.org_slug}/workspaces/#{socket.assigns.ws_slug}/observability/trends?#{[days: parse_days(days)]}"
     )}
  end

  @impl true
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  def render(assigns) do
    ~H"""
    <section id="observability-trends" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">Trends</h1>
          <p class="text-sm text-muted-foreground">
            Local run, finding, cost, and import trends across a rolling N-day window.
          </p>
        </div>

        <form id="trends-days" phx-change="select_days">
          <select
            name="days"
            class="cursor-pointer rounded-full border border-border bg-card px-3 py-1.5 text-sm text-foreground outline-none transition hover:border-primary/40 focus:border-primary"
          >
            <option value="1" selected={@selected_days == 1}>Today</option>
            <option value="3" selected={@selected_days == 3}>3 days</option>
            <option value="7" selected={@selected_days == 7}>1 week</option>
            <option value="30" selected={@selected_days == 30}>1 month</option>
          </select>
        </form>
      </div>

      <p class="text-xs text-muted-foreground">
        example:
        <code class="mx-1 rounded bg-muted px-1.5 py-0.5 font-mono text-xs text-foreground">
          controlkeel obs trends --days 30
        </code>
        <span class="text-muted-foreground/70">
          · controlkeel obs trends (no flag) defaults to 7 days
        </span>
      </p>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article
          id="observability-trends-runs"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Runs</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{@trends.totals.runs}</p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@trends.totals.red_runs} red · {@trends.totals.yellow_runs} yellow · {@trends.totals.green_runs} green
          </p>
        </article>

        <article
          id="observability-trends-findings"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Findings</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@trends.totals.active_findings}
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@trends.totals.blocked_findings} blocked
          </p>
        </article>

        <article
          id="observability-trends-costs"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Estimated spend</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {format_currency(@trends.totals.estimated_cost_cents)}
          </p>
        </article>

        <article
          id="observability-trends-imports"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Imports</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{@trends.totals.imports}</p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@trends.totals.verified_imports} verified · {@trends.totals.non_verified_imports} non-verified
          </p>
        </article>
      </div>

      <%= if @trends.recommendations != [] do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
          <.section_title>Recommendations</.section_title>
          <ul class="space-y-2 text-sm leading-relaxed text-muted-foreground list-disc ml-5">
            <%= for recommendation <- @trends.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </section>
      <% end %>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Daily series</.section_title>
        <div class="max-h-[650px] space-y-3 overflow-y-auto divide-y divide-border">
          <%= for day <- @trends.series do %>
            <div id={"observability-trend-#{day.date}"} class="space-y-2 pt-3 first:pt-0">
              <p class="text-sm font-medium text-foreground">{day.date}</p>
              <p class="text-xs text-muted-foreground">
                Runs {day.runs} · red {day.health.red} · yellow {day.health.yellow} · green {day.health.green}
              </p>
              <div class="flex gap-1">
                <div class="h-1.5 flex-1 overflow-hidden rounded-full bg-destructive/15">
                  <div
                    class="h-full rounded-full bg-destructive"
                    style={"width: #{bar_width(day.health.red, @trends.totals.runs)}%"}
                  />
                </div>
                <div class="h-1.5 flex-1 overflow-hidden rounded-full bg-warning/15">
                  <div
                    class="h-full rounded-full bg-warning"
                    style={"width: #{bar_width(day.health.yellow, @trends.totals.runs)}%"}
                  />
                </div>
                <div class="h-1.5 flex-1 overflow-hidden rounded-full bg-success/15">
                  <div
                    class="h-full rounded-full bg-success"
                    style={"width: #{bar_width(day.health.green, @trends.totals.runs)}%"}
                  />
                </div>
              </div>
              <p class="text-xs text-muted-foreground">
                Findings {day.active_findings} / {day.blocked_findings} blocked · cost {format_currency(
                  day.estimated_cost_cents
                )} · imports {day.imports} ({day.verified_imports} verified)
              </p>
            </div>
          <% end %>
        </div>
      </section>
    </section>
    """
  end

  defp load_trends(socket, days) do
    opts = Keyword.put(socket.assigns.opts, :days, days)

    socket
    |> assign(:trends, Observability.trends(opts))
    |> assign(:selected_days, days)
  end

  defp parse_days(nil), do: 7

  defp parse_days(value) do
    case Integer.parse(to_string(value)) do
      {days, ""} when days > 0 -> days
      _ -> 7
    end
  end

  defp bar_width(_value, 0), do: 0
  defp bar_width(value, total), do: min(100, round(value * 100 / total))

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
