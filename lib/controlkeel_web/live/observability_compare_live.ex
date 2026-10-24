defmodule ControlKeelWeb.ObservabilityCompareLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability
  alias ControlKeelWeb.WorkspaceScope

  @groupings ~w(source model provider tool)

  @impl true
  def mount(params, _session, socket) do
    case WorkspaceScope.assign_scope(socket, params, "Compare") do
      {:ok, socket} ->
        {:ok, socket |> assign(:page_title, "Observability Compare") |> load_page(params)}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    WorkspaceScope.on_params(socket, params, &load_page/2)
  end

  defp load_page(socket, _params) do
    base_opts = [workspace_id: socket.assigns.workspace.id]

    comparisons =
      Enum.map(@groupings, fn group ->
        {group, Observability.comparison(Keyword.put(base_opts, :by, group))}
      end)

    primary = comparisons |> List.first() |> elem(1)

    socket
    |> assign(:comparison, primary)
    |> assign(:comparisons, comparisons)
  end

  @impl true
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  def render(assigns) do
    ~H"""
    <section id="observability-compare" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Compare invocations
          </h1>
          <p class="text-sm text-muted-foreground">
            Local host, model, provider, and tool comparison from recorded invocation metrics.
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
          <span id="observability-compare-count" class={neutral_pill_class()}>
            {@comparison.totals.invocations} invocation(s)
          </span>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Invocations</p>
          <p class="text-2xl font-semibold text-foreground/90">
            {@comparison.totals.invocations}
          </p>
          <p class="text-xs text-muted-foreground">
            {@comparison.totals.sessions} session(s)
          </p>
        </section>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Estimated spend</p>
          <p class="text-2xl font-semibold text-foreground/90">
            {format_currency(@comparison.totals.estimated_cost_cents)}
          </p>
          <p class="text-xs text-muted-foreground">Across compared calls</p>
        </section>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Tokens</p>
          <p class="text-2xl font-semibold text-foreground/90">
            {@comparison.totals.input_tokens + @comparison.totals.cached_input_tokens +
              @comparison.totals.output_tokens}
          </p>
          <p class="text-xs text-muted-foreground">Input, cached, and output</p>
        </section>
      </div>

      <%= if @comparison.recommendations != [] do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
          <.section_title>Recommendations</.section_title>
          <%= for recommendation <- @comparison.recommendations do %>
            <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
          <% end %>
        </section>
      <% end %>

      <div class="space-y-4">
        <.section_title>Group comparisons</.section_title>
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <%= for {grouping, comparison} <- @comparisons do %>
            <section
              id={"observability-compare-by-#{grouping}"}
              class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
            >
              <div class="flex items-center justify-between gap-2">
                <p class="text-sm font-medium text-muted-foreground">
                  Compared by <span class="font-semibold text-foreground">{grouping}</span>
                </p>
                <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
                  {length(comparison.groups)} group(s)
                </span>
              </div>

              <%= if comparison.groups == [] do %>
                <p class="text-sm text-muted-foreground">
                  No invocation data is available for comparison yet.
                </p>
              <% else %>
                <div class="divide-y divide-border">
                  <%= for group <- comparison.groups do %>
                    <div class="space-y-1 py-2.5 first:pt-0 last:pb-0">
                      <p class="text-sm font-medium text-foreground">{group.name}</p>
                      <p class="text-xs text-muted-foreground">
                        {group.invocations} call(s) · {format_currency(group.estimated_cost_cents)} · {group.cost_per_call_cents} cent(s)/call · {group.tokens_per_call} token(s)/call
                      </p>
                      <%= if group.decisions && group.decisions != %{} do %>
                        <p class="text-xs text-muted-foreground">
                          Decisions: {format_frequency(group.decisions)}
                        </p>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </section>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
