defmodule ControlKeelWeb.ObservabilityMemoryQualityLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Observability
  alias ControlKeel.Repo
  alias ControlKeelWeb.WorkspaceAccess

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug} = params, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      stale_days = parse_days(params["stale_days"])
      opts = [workspace_id: workspace.id, stale_days: stale_days]
      quality = Observability.memory_quality(opts)

      {:ok,
       socket
       |> assign(:page_title, "Memory quality")
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
           %{label: "Memory quality", to: nil}
         ]
       )
       |> assign(:quality, quality)}
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

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-memory-quality" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Memory quality
          </h1>
          <p class="text-sm text-muted-foreground">
            Summary-only signals for stale, duplicate, superseded, and missed workspace memory.
          </p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <span class="rounded-full bg-warning/10 px-3 py-1.5 text-sm font-semibold text-warning ring-1 ring-warning/20">
            stale ≥ {@quality.stale_days} days
          </span>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article
          id="observability-memory-quality-total"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Memory records</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">{@quality.totals.records}</p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@quality.totals.active} active · {@quality.totals.archived} archived
          </p>
        </article>

        <article
          id="observability-memory-quality-stale"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Stale candidates</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@quality.totals.stale_candidates}
          </p>
        </article>

        <article
          id="observability-memory-quality-duplicates"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Duplicate clusters</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@quality.totals.duplicate_clusters}
          </p>
        </article>

        <article
          id="observability-memory-quality-missed"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Missed-memory sessions</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@quality.totals.missed_memory_sessions}
          </p>
        </article>
      </div>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-2">
        <.section_title>Distribution</.section_title>
        <p class="text-xs text-muted-foreground">
          Types: {format_frequency(@quality.distributions.by_type)}
        </p>
        <p class="text-xs text-muted-foreground">
          Sources: {format_frequency(@quality.distributions.by_source)}
        </p>
      </section>

      <%= if @quality.recommendations != [] do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
          <.section_title>Recommendations</.section_title>
          <%= for recommendation <- @quality.recommendations do %>
            <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
          <% end %>
        </section>
      <% end %>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Stale memory</.section_title>
        <%= if @quality.stale_candidates == [] do %>
          <p class="text-sm text-muted-foreground">No stale memory candidates detected.</p>
        <% else %>
          <div class="space-y-2">
            <%= for record <- @quality.stale_candidates do %>
              <div
                id={"observability-memory-quality-stale-#{record.id}"}
                class="rounded-lg px-3 py-2 bg-muted/30 space-y-1"
              >
                <p class="text-sm font-medium text-foreground">{record.title}</p>
                <p class="text-xs text-muted-foreground">
                  {record.record_type} · {record.age_days} day(s) old · {record.source_type}
                </p>
                <p class="text-xs text-muted-foreground">{record.summary}</p>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Duplicate clusters</.section_title>
        <%= if @quality.duplicate_clusters == [] do %>
          <p class="text-sm text-muted-foreground">No duplicate clusters detected.</p>
        <% else %>
          <div class="space-y-2">
            <%= for cluster <- @quality.duplicate_clusters do %>
              <div class="rounded-lg px-3 py-2 bg-muted/30">
                <p class="text-sm font-medium text-foreground">{cluster.key}</p>
                <p class="text-xs text-muted-foreground">{cluster.count} matching record(s)</p>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Contradiction or superseded candidates</.section_title>
        <%= if @quality.contradiction_candidates == [] do %>
          <p class="text-sm text-muted-foreground">
            No contradiction or superseded markers detected.
          </p>
        <% else %>
          <div class="space-y-2">
            <%= for record <- @quality.contradiction_candidates do %>
              <div
                id={"observability-memory-quality-contradiction-#{record.id}"}
                class="rounded-lg px-3 py-2 bg-muted/30 space-y-1"
              >
                <p class="text-sm font-medium text-foreground">{record.title}</p>
                <p class="text-xs text-muted-foreground">{record.summary}</p>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Missed-memory sessions</.section_title>
        <%= if @quality.missed_memory_sessions == [] do %>
          <p class="text-sm text-muted-foreground">
            No sessions with evidence but missing memory detected.
          </p>
        <% else %>
          <div class="space-y-2">
            <%= for session <- @quality.missed_memory_sessions do %>
              <div
                id={"observability-memory-quality-missed-#{session.id}"}
                class="rounded-lg px-3 py-2 bg-muted/30 space-y-1"
              >
                <p class="text-sm font-medium text-foreground">{session.title}</p>
                <p class="text-xs text-muted-foreground">
                  {session.findings} finding(s) · {session.reviews} review(s) · {session.invocations} invocation(s)
                </p>
                <p class="text-xs text-muted-foreground">{session.recommendation}</p>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </section>
    """
  end

  defp parse_days(nil), do: 30

  defp parse_days(value) do
    case Integer.parse(to_string(value)) do
      {days, ""} when days > 0 -> days
      _ -> 30
    end
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
