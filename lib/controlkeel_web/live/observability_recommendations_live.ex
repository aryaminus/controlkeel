defmodule ControlKeelWeb.ObservabilityRecommendationsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session =
      Mission.list_recent_sessions_for_user(socket.assigns[:current_user], 1) |> List.first()

    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    recommendations = Observability.recommendations(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Recommendations")
     |> assign(:recommendations, recommendations)}
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

      <CommandPill.command_pill command="controlkeel obs recommend" />

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
