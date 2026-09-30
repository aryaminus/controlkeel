defmodule ControlKeelWeb.ObservabilityCostsLive do
  use ControlKeelWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Budget.CostOptimizer
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Observability
  alias ControlKeel.Repo
  alias ControlKeelWeb.CommandPill
  alias ControlKeelWeb.WorkspaceAccess

  on_mount ControlKeelWeb.CommandPill

  @groupings ~w(model tool source provider)

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug} = params, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      base_opts = [workspace_id: workspace.id]
      by = normalize_grouping(params["by"])
      # Single invocation fetch powers costs, group breakdowns, and the
      # folded invocation comparison (see Observability.costs_comparison/1).
      report = Observability.costs_comparison(Keyword.put(base_opts, :by, by))

      recent_session = Mission.list_recent_sessions(1, workspace.id) |> List.first()
      {:ok, suggestions} = load_suggestions(recent_session)

      {:ok, comparison} =
        CostOptimizer.compare_agents("Agent cost comparison", estimated_tokens: 10_000)

      {:ok,
       socket
       |> assign(:page_title, "Observability Costs")
       |> assign(:workspace, workspace)
       |> assign(:nav_org, workspace.org)
       |> assign(:nav_workspace, workspace)
       |> assign(
         :breadcrumbs,
         [
           %{label: workspace.org.name, to: ~p"/#{workspace.org.slug}"},
           %{
             label: workspace.name,
             to: ~p"/#{workspace.org.slug}/workspaces/#{workspace.slug}"
           },
           %{label: "Costs", to: nil}
         ]
       )
       |> assign(:base_opts, base_opts)
       |> assign(:groupings, @groupings)
       |> assign(:by, by)
       |> assign(:costs, report.costs)
       |> assign(:inv_comparison, report.comparison)
       |> assign(:grouped_costs, report.grouped_costs)
       |> assign(:suggestions, suggestions)
       |> assign(:comparison, comparison)}
    else
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

  @impl true
  def handle_params(%{"by" => by}, _uri, socket) do
    by = normalize_grouping(by)

    if by == socket.assigns.by do
      {:noreply, socket}
    else
      report = Observability.costs_comparison(Keyword.put(socket.assigns.base_opts, :by, by))

      {:noreply,
       socket
       |> assign(:by, by)
       |> assign(:costs, report.costs)
       |> assign(:inv_comparison, report.comparison)
       |> assign(:grouped_costs, report.grouped_costs)}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp normalize_grouping(by) when by in @groupings, do: by
  defp normalize_grouping(_), do: "model"

  defp check_org_slug(%Workspace{org_id: org_id}, %{slug: slug}) when is_integer(org_id) do
    case Accounts.get_org_by_slug(slug) do
      %Org{id: ^org_id} -> :ok
      _ -> {:error, "Workspace does not belong to this organization."}
    end
  end

  defp check_org_slug(_, _), do: {:error, "Workspace does not belong to this organization."}

  defp check_workspace_access(workspace, assigns) do
    case WorkspaceAccess.check(workspace, assigns[:current_user]) do
      :ok -> :ok
      {:error, :unbound} -> {:error, "Workspace is not bound to an org."}
      {:error, :forbidden} -> {:error, "Workspace belongs to a different organization."}
      {:error, :needs_admin} -> {:error, "Viewer role or higher required."}
    end
  end

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-costs" class="w-full space-y-5">
      <div class="space-y-2">
        <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">Costs</h1>
        <p class="text-sm text-muted-foreground">
          Estimated spend, token usage, and invocation comparison grouped by model, tool, source, or provider.
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <CommandPill.command_pill command="controlkeel obs costs" />
        <CommandPill.command_pill command="controlkeel obs compare" />
      </div>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <section
          id="observability-costs-suggestions"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
        >
          <div class="flex items-center justify-between gap-3">
            <.section_title>Cost optimization suggestions</.section_title>
            <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
              {length(@suggestions)} suggestion(s)
            </span>
          </div>
          <%= if @suggestions == [] do %>
            <p class="text-sm text-muted-foreground">
              No cost optimization suggestions at this time.
            </p>
          <% else %>
            <div class="divide-y divide-border">
              <%= for suggestion <- @suggestions do %>
                <div class="space-y-1.5 py-3 first:pt-0 last:pb-0">
                  <div class="flex items-center justify-between gap-3">
                    <p class="text-sm font-medium text-foreground">{suggestion.title}</p>
                    <span class={priority_pill_class(suggestion.priority)}>
                      {suggestion.priority}
                    </span>
                  </div>
                  <p class="text-xs leading-relaxed text-muted-foreground">
                    {suggestion.description}
                  </p>
                  <%= if suggestion.savings_percent do %>
                    <p class="text-xs font-medium text-success">
                      Potential savings: {suggestion.savings_percent}%
                    </p>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </section>

        <section
          id="observability-costs-comparison"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
        >
          <div class="flex items-center justify-between gap-3">
            <.section_title>Agent cost comparison</.section_title>
            <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
              {format_number(@comparison.estimated_tokens)} tokens
            </span>
          </div>
          <%= if @comparison.comparisons == [] do %>
            <p class="text-sm text-muted-foreground">No agent cost comparison available.</p>
          <% else %>
            <div class="divide-y divide-border">
              <%= for comparison <- @comparison.comparisons do %>
                <div class="flex items-center justify-between gap-3 py-2.5 first:pt-0 last:pb-0">
                  <div class="min-w-0">
                    <p class="text-sm font-medium text-foreground">{comparison.agent}</p>
                    <p class="text-xs text-muted-foreground">
                      {comparison.provider} / {comparison.model}
                    </p>
                  </div>
                  <span class={cheapest_pill_class(comparison, @comparison.cheapest)}>
                    {format_currency(comparison.estimated_cost_cents)}
                  </span>
                </div>
              <% end %>
            </div>
            <%= if @comparison.savings_range > 0 do %>
              <p class="text-xs font-medium text-success">
                Potential savings vs most expensive: {format_currency(@comparison.savings_range)}
              </p>
            <% end %>
          <% end %>
        </section>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Invocations</p>
          <p class="text-2xl font-semibold text-foreground/90">{@costs.totals.invocations}</p>
          <p class="text-xs text-muted-foreground">{@costs.totals.sessions} session(s)</p>
        </section>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Estimated spend</p>
          <p class="text-2xl font-semibold text-foreground/90">
            {format_currency(@costs.totals.estimated_cost_cents)}
          </p>
          <p class="text-xs text-muted-foreground">Local invocation estimate</p>
        </section>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Input tokens</p>
          <p class="text-2xl font-semibold text-foreground/90">{@costs.totals.input_tokens}</p>
          <p class="text-xs text-muted-foreground">
            {@costs.totals.cached_input_tokens} cached
          </p>
        </section>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Output tokens</p>
          <p class="text-2xl font-semibold text-foreground/90">{@costs.totals.output_tokens}</p>
          <p class="text-xs text-muted-foreground">Across recorded calls</p>
        </section>
      </div>

      <%= if @costs.recommendations != [] do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
          <.section_title>Recommendations</.section_title>
          <%= for recommendation <- @costs.recommendations do %>
            <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
          <% end %>
        </section>
      <% end %>

      <section id="compare" class="space-y-4">
        <div class="flex items-start justify-between gap-4 flex-wrap">
          <div class="space-y-2">
            <.section_title>Compare invocations</.section_title>
            <p class="text-xs text-muted-foreground">
              Local host, model, provider, and tool comparison from recorded invocation metrics.
            </p>
          </div>
          <span id="observability-compare-count" class={neutral_pill_class()}>
            {@inv_comparison.totals.invocations} invocation(s)
          </span>
        </div>

        <div id="observability-costs-grouping" class="flex flex-wrap items-center gap-2">
          <span class="text-sm text-muted-foreground">Grouped by</span>
          <%= for grouping <- @groupings do %>
            <.link
              patch={~p"/#{@workspace.org.slug}/workspaces/#{@workspace.slug}/costs?#{[by: grouping]}"}
              class={
                if grouping == @by,
                  do:
                    "rounded-full bg-primary/10 px-3 py-1.5 text-sm font-semibold text-primary ring-1 ring-primary/20",
                  else:
                    "rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground hover:text-primary"
              }
            >
              {grouping}
            </.link>
          <% end %>
        </div>

        <%= if @inv_comparison.recommendations != [] do %>
          <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
            <.section_title>Comparison recommendations</.section_title>
            <%= for recommendation <- @inv_comparison.recommendations do %>
              <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
            <% end %>
          </section>
        <% end %>

        <section
          id={"observability-compare-by-#{@by}"}
          class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
        >
          <div class="flex items-center justify-between gap-2">
            <p class="text-sm font-medium text-muted-foreground">
              Compared by <span class="font-semibold text-foreground">{@by}</span>
            </p>
            <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
              {length(@inv_comparison.groups)} group(s)
            </span>
          </div>

          <%= if @inv_comparison.groups == [] do %>
            <p class="text-sm text-muted-foreground">
              No invocation data is available for comparison yet.
            </p>
          <% else %>
            <div class="divide-y divide-border">
              <%= for group <- @inv_comparison.groups do %>
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
      </section>

      <div class="space-y-4">
        <.section_title>Group breakdown</.section_title>
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <%= for {grouping, costs} <- @grouped_costs do %>
            <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
              <div class="flex items-center justify-between gap-2">
                <p class="text-sm font-medium text-muted-foreground">Grouped by {grouping}</p>
                <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
                  {length(costs.groups)} group(s)
                </span>
              </div>

              <%= if costs.groups == [] do %>
                <p class="text-sm text-muted-foreground">
                  No invocation cost data has been recorded yet.
                </p>
              <% else %>
                <div class="divide-y divide-border">
                  <%= for group <- costs.groups do %>
                    <div class="py-2.5 first:pt-0 last:pb-0">
                      <p class="text-sm font-medium text-foreground">{group.name}</p>
                      <p class="mt-1 text-xs text-muted-foreground">
                        {group.invocations} call(s) · {format_currency(group.estimated_cost_cents)} · {group.input_tokens} input · {group.output_tokens} output
                      </p>
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

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end

  defp format_number(number) when is_integer(number),
    do: number |> Integer.to_string() |> add_thousands_separators()

  defp format_number(number), do: to_string(number)

  defp add_thousands_separators(digits) do
    digits
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp load_suggestions(nil), do: {:ok, []}

  defp load_suggestions(session) do
    spending =
      from(i in Invocation,
        where: i.session_id == ^session.id,
        select: %{
          estimated_cost_cents: i.estimated_cost_cents,
          tool: i.tool,
          metadata: i.metadata
        }
      )
      |> Repo.all()

    CostOptimizer.suggest(session.id, spending: spending)
  end

  defp priority_pill_class("high"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp priority_pill_class("medium"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp priority_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium capitalize ring-1 bg-muted text-foreground ring-border"

  defp cheapest_pill_class(comparison, cheapest) do
    base = "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium ring-1"

    if cheapest && comparison.agent == cheapest.agent do
      "#{base} bg-success/10 text-success ring-success/20"
    else
      "#{base} bg-muted text-foreground ring-border"
    end
  end
end
