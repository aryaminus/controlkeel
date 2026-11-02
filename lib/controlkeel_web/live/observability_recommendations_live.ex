defmodule ControlKeelWeb.ObservabilityRecommendationsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability
  alias ControlKeelWeb.WorkspaceScope

  @impl true
  def mount(params, _session, socket) do
    case WorkspaceScope.assign_scope(socket, params, "Recommendations") do
      {:ok, socket} ->
        {:ok, socket |> assign(:page_title, "Observability Recommendations") |> load_page(params)}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    WorkspaceScope.on_params(socket, params, &load_page/2)
  end

  defp load_page(socket, _params) do
    workspace = socket.assigns.workspace

    recommendations =
      [workspace_id: workspace.id]
      |> Observability.recommendations()
      |> scope_recommendation_links(workspace)

    assign(socket, :recommendations, recommendations)
  end

  # Recommendation links are authored as global paths; rewrite the
  # observability ones to this workspace so "Open related view" never
  # bounces multi-workspace visitors through the global resolver.
  # Non-observability links (e.g. /proofs) pass through untouched.
  defp scope_recommendation_links(recommendations, workspace) do
    prefix = "/#{workspace.org.slug}/workspaces/#{workspace.slug}"

    Map.update!(recommendations, :actions, fn actions ->
      Enum.map(actions, fn
        %{link: "/observability" <> rest} = action ->
          %{action | link: prefix <> "/observability" <> rest}

        action ->
          action
      end)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-recommendations" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Recommendations
          </h1>
          <p class="text-sm text-muted-foreground">
            Actionable next steps derived from the current workspace’s runs, problems, and evidence.
          </p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <span class={health_pill_class(@recommendations.health)}>
            {@recommendations.health}
          </span>
          <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
            {@recommendations.count} action(s)
          </span>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Actions</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{@recommendations.count}</p>
          <p class="mt-1 text-xs text-muted-foreground">Prioritized by current local evidence</p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Categories</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {length(@recommendations.categories)}
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {Enum.join(@recommendations.categories, ", ")}
          </p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Workspace</p>
          <p class="mt-2 truncate text-xl font-semibold text-foreground/90">
            {@recommendations.workspace.name}
          </p>
          <p class="mt-1 text-xs text-muted-foreground">Local-first summary</p>
        </article>
      </div>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Active recommendations</.section_title>
        <%= if @recommendations.actions == [] do %>
          <p class="text-sm text-muted-foreground">
            No recommendations are currently active.
          </p>
        <% else %>
          <div class="divide-y divide-border">
            <%= for action <- @recommendations.actions do %>
              <div
                id={"observability-recommendation-#{action.id}"}
                class="space-y-2 py-3 first:pt-0 last:pb-0"
              >
                <div class="flex items-start justify-between gap-4">
                  <div class="min-w-0 space-y-1">
                    <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                      {action.category}
                    </p>
                    <p class="text-sm font-medium text-foreground">{action.title}</p>
                  </div>
                  <span class={priority_pill_class(action.priority)}>{action.priority}</span>
                </div>
                <p class="text-xs text-muted-foreground">{action.evidence}</p>
                <p class="text-sm text-foreground">{action.suggested_action}</p>
                <div class="flex flex-wrap items-center gap-4 text-xs text-muted-foreground">
                  <span>Source: {action.source}</span>
                  <span>Human gate: {action.human_gate_required}</span>
                  <.link
                    navigate={action.link}
                    class="inline-flex items-center gap-2 text-sm font-medium text-primary transition hover:text-primary"
                  >
                    Open related view <.icon name="hero-arrow-up-right" class="size-3" />
                  </.link>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </section>
    """
  end

  defp health_pill_class("red"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp health_pill_class("yellow"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp health_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp priority_pill_class("critical"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp priority_pill_class("high"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp priority_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium ring-1 bg-muted text-foreground ring-border"
end
