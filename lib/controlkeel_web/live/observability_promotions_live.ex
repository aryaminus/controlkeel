defmodule ControlKeelWeb.ObservabilityPromotionsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability
  alias ControlKeelWeb.WorkspaceScope

  @impl true
  def mount(params, _session, socket) do
    case WorkspaceScope.assign_scope(socket, params, "Promotions") do
      {:ok, socket} ->
        {:ok,
         socket
         |> assign(:page_title, "Observability Promotion Candidates")
         |> load_page(params)}

      {:error, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    WorkspaceScope.on_params(socket, params, &load_page/2)
  end

  defp load_page(socket, _params) do
    promotions = Observability.promotion_candidates(workspace_id: socket.assigns.workspace.id)
    assign(socket, :promotions, promotions)
  end

  @impl true
  def render(%{scope_error: error} = assigns) when not is_nil(error), do: ~H""

  def render(assigns) do
    ~H"""
    <section id="observability-promotions" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Promotion candidates
          </h1>
          <p class="text-sm text-muted-foreground">
            Advisory, human-gated promotion candidates backed by local observability evidence.
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
          <span id="observability-promotions-count" class={neutral_pill_class()}>
            {@promotions.count} candidate(s)
          </span>
        </div>
      </div>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
        <p class="text-sm font-medium text-muted-foreground">Execution boundary</p>
        <p class="text-base font-semibold text-foreground/90">
          Promotion execution: {@promotions.promotion_execution}
        </p>
        <p class="text-xs text-muted-foreground">
          This page does not mutate policy, router, prompt, or autofix artifacts.
        </p>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
        <.section_title>Recommendations</.section_title>
        <%= if @promotions.recommendations == [] do %>
          <p class="text-sm text-muted-foreground">No promotion recommendations yet.</p>
        <% else %>
          <%= for recommendation <- @promotions.recommendations do %>
            <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
          <% end %>
        <% end %>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Candidates</.section_title>
        <%= if @promotions.candidates == [] do %>
          <p class="text-sm text-muted-foreground">No promotion candidates yet.</p>
        <% else %>
          <div class="divide-y divide-border">
            <%= for candidate <- @promotions.candidates do %>
              <div
                id={"observability-promotion-candidate-#{candidate.id}"}
                class="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0"
              >
                <div class="min-w-0">
                  <p class="text-sm font-medium text-foreground">{candidate.rule_id}</p>
                  <p class="mt-1 text-xs text-muted-foreground">{candidate.suggested_action}</p>
                </div>
                <span class={readiness_pill_class(candidate.readiness)}>{candidate.readiness}</span>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </section>
    """
  end

  defp readiness_pill_class("ready"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp readiness_pill_class("needs_draft"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp readiness_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium capitalize ring-1 bg-muted text-foreground ring-border"
end
