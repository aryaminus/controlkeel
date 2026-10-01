defmodule ControlKeelWeb.ObservabilityEvalsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Observability
  alias ControlKeel.Repo
  alias ControlKeelWeb.CommandPill
  alias ControlKeelWeb.WorkspaceAccess

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug} = _params, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      opts = [workspace_id: workspace.id]
      eval_candidates = Observability.eval_candidates(opts)
      saved = Observability.saved_eval_candidates(opts)

      {:ok,
       socket
       |> assign(:page_title, "Observability Eval Candidates")
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
           %{label: "Evals", to: nil}
         ]
       )
       |> assign(:opts, opts)
       |> assign(:eval_candidates, eval_candidates)
       |> assign(:saved, saved)
       |> assign(:can_mutate, can_mutate?(workspace, socket.assigns))}
    else
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

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

  # Mutation gate (viewer reads stay open): the save button renders and the
  # event runs only for admin/owner. Local mode always passes.
  defp can_mutate?(workspace, assigns) do
    WorkspaceAccess.check(workspace, assigns[:current_user], "admin") == :ok
  end

  @impl true
  def handle_event("save-candidates", _params, socket) do
    with %Workspace{} = workspace <- socket.assigns[:workspace],
         :ok <- WorkspaceAccess.check(workspace, socket.assigns[:current_user], "admin") do
      opts = socket.assigns.opts
      result = Observability.save_eval_candidates(opts)

      socket =
        socket
        |> assign(:eval_candidates, Observability.eval_candidates(opts))
        |> assign(:saved, Observability.saved_eval_candidates(opts))

      {:noreply, put_flash(socket, :info, save_summary_message(result))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Admin or owner role required.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-evals-page" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Eval candidates
          </h1>
          <p class="text-sm text-muted-foreground">
            Advisory regression candidates derived from grouped problems and feedback evidence.
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
          <span id="observability-evals-health" class={health_pill_class(@eval_candidates.health)}>
            {@eval_candidates.health}
          </span>
          <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
            {@eval_candidates.count} candidate(s)
          </span>
          <button
            :if={@can_mutate}
            id="observability-evals-save"
            type="button"
            phx-click="save-candidates"
            class="inline-flex items-center rounded-lg bg-primary px-3 py-1.5 text-sm font-semibold text-primary-foreground transition hover:opacity-90"
          >
            Review &amp; save candidates
          </button>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <CommandPill.command_pill command="controlkeel obs evals" />
        <p class="text-xs text-muted-foreground">
          Save persists the current advisory candidates locally for human-gated review.
        </p>
      </div>

      <%= if @eval_candidates.recommendations != [] do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
          <.section_title>Recommended next actions</.section_title>
          <ul class="space-y-2 text-sm leading-relaxed text-muted-foreground list-disc ml-5">
            <%= for recommendation <- @eval_candidates.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </section>
      <% end %>

      <section
        id="observability-evals-list"
        class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
      >
        <.section_title>Active candidates</.section_title>
        <%= if @eval_candidates.candidates == [] do %>
          <p class="text-sm text-muted-foreground">
            No eval candidates are currently active.
          </p>
        <% else %>
          <div class="divide-y divide-border">
            <%= for candidate <- @eval_candidates.candidates do %>
              <div
                id={"observability-eval-#{candidate.id}"}
                class="space-y-2 py-3 first:pt-0 last:pb-0"
              >
                <div class="flex items-center justify-between gap-4">
                  <div class="min-w-0 space-y-1">
                    <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                      {candidate.category}
                    </p>
                    <p class="text-sm font-medium text-foreground">{candidate.title}</p>
                  </div>
                  <span class={priority_pill_class(candidate.priority)}>{candidate.priority}</span>
                </div>
                <p class="text-xs text-muted-foreground">
                  {candidate.rule_id} · {candidate.finding_count} finding(s) · {candidate.affected_session_count} session(s)
                </p>
                <p class="text-sm leading-relaxed text-foreground">
                  {candidate.evidence_summary}
                </p>
                <p class="text-xs text-muted-foreground">
                  Benchmark hint: {candidate.benchmark_hint}
                </p>
                <p class="text-xs text-muted-foreground">
                  Human gate required: {candidate.human_gate_required}
                </p>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <article
          id="observability-persisted-evals-status"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Saved status</p>
          <p class="mt-2 text-lg font-semibold text-foreground/90">
            {format_frequency(@saved.by_status)}
          </p>
        </article>

        <article
          id="observability-persisted-evals-priority"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Saved priority</p>
          <p class="mt-2 text-lg font-semibold text-foreground/90">
            {format_frequency(@saved.by_priority)}
          </p>
        </article>
      </div>

      <section
        id="observability-persisted-evals-list"
        class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
      >
        <div class="flex items-center justify-between gap-3">
          <.section_title>Saved eval candidates</.section_title>
          <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
            {@saved.count} saved
          </span>
        </div>
        <%= if @saved.candidates == [] do %>
          <p class="text-sm text-muted-foreground">No saved eval candidates yet.</p>
        <% else %>
          <div class="divide-y divide-border">
            <%= for candidate <- @saved.candidates do %>
              <div
                id={"observability-persisted-eval-#{candidate.id}"}
                class="space-y-2 py-3 first:pt-0 last:pb-0"
              >
                <div class="flex items-center justify-between gap-4">
                  <div class="min-w-0 space-y-1">
                    <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                      {candidate.category || "uncategorized"}
                    </p>
                    <p class="text-sm font-medium text-foreground">{candidate.title}</p>
                  </div>
                  <span class="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-foreground">
                    {candidate.status}
                  </span>
                </div>
                <p class="text-xs text-muted-foreground">
                  {candidate.rule_id} · {candidate.priority} · human gate {candidate.human_gate_required}
                </p>
                <p class="text-sm leading-relaxed text-foreground">
                  {candidate.evidence_summary}
                </p>
                <p class="text-xs text-muted-foreground">Next: {candidate.suggested_action}</p>
                <p class="text-xs text-muted-foreground">
                  Benchmark hint: {candidate.benchmark_hint || "none"}
                </p>
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

  defp save_summary_message(%{stored: 0, existing: _existing, source_count: 0}) do
    "No active eval candidates to save."
  end

  defp save_summary_message(%{stored: 0, existing: existing}) when existing > 0 do
    "Nothing new to save — #{existing} candidate(s) already saved."
  end

  defp save_summary_message(%{stored: stored, existing: existing}) do
    count_part = "Saved #{stored} candidate(s)"
    existing_part = if existing > 0, do: " · #{existing} already existed", else: ""
    count_part <> existing_part <> "."
  end

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(4)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
