defmodule ControlKeelWeb.ObservabilityImportsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Observability
  alias ControlKeel.Repo
  alias ControlKeelWeb.WorkspaceAccess

  @impl true
  def mount(%{"ws_slug" => ws_slug, "org_slug" => slug} = _params, _session, socket) do
    with %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      opts = [workspace_id: workspace.id]
      imports = Observability.imports(opts)

      {:ok,
       socket
       |> assign(:page_title, "Observability imports")
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
           %{label: "Imports", to: nil}
         ]
       )
       |> assign(:imports, imports)}
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
    <section id="observability-imports" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Imported snapshots
          </h1>
          <p class="text-sm text-muted-foreground">
            Local persisted observability envelopes, listed as summary-only evidence snapshots.
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
          <span id="observability-imports-count" class={neutral_pill_class()}>
            {@imports.count} persisted
          </span>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <article
          id="observability-imports-integrity"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Integrity</p>
          <p class="mt-2 text-lg font-semibold text-foreground/90">
            {format_frequency(@imports.by_integrity)}
          </p>
        </article>
        <article
          id="observability-imports-health"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Health</p>
          <p class="mt-2 text-lg font-semibold text-foreground/90">
            {format_frequency(@imports.by_health)}
          </p>
        </article>
      </div>

      <%= if @imports.recommendations != [] do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
          <.section_title>Recommendations</.section_title>
          <%= for recommendation <- @imports.recommendations do %>
            <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
          <% end %>
        </section>
      <% end %>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Recent imports</.section_title>
        <%= if @imports.recent == [] do %>
          <p class="text-sm text-muted-foreground">
            No persisted observability imports yet.
          </p>
        <% else %>
          <div class="divide-y divide-border">
            <%= for imported <- @imports.recent do %>
              <div
                id={"observability-import-#{imported.id}"}
                class="space-y-3 py-4 first:pt-0 last:pb-0"
              >
                <p class="text-sm font-medium text-foreground">
                  {imported.original_session_title || "Unknown session"}
                </p>
                <dl class="grid grid-cols-2 gap-3 text-xs md:grid-cols-4">
                  <div>
                    <dt class="text-muted-foreground">Imported</dt>
                    <dd class="mt-0.5 font-medium text-foreground">
                      {imported.imported_at || "unknown time"}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Exported</dt>
                    <dd class="mt-0.5 font-medium text-foreground">
                      {imported.exported_at || "unknown time"}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Session</dt>
                    <dd class="mt-0.5 font-medium text-foreground">
                      #{imported.original_session_id || "unknown"}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Health</dt>
                    <dd class="mt-0.5 font-medium text-foreground">{imported.health}</dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Problem groups</dt>
                    <dd class="mt-0.5 font-medium text-foreground">{imported.problem_groups}</dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Findings</dt>
                    <dd class="mt-0.5 font-medium text-foreground">
                      {imported.total_problem_findings}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Integrity</dt>
                    <dd class="mt-0.5 font-medium text-foreground">
                      {imported.integrity_status}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Mutation</dt>
                    <dd class="mt-0.5 font-medium text-foreground">{imported.mutation}</dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Schema</dt>
                    <dd class="mt-0.5 font-medium text-foreground">{imported.schema_version}</dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Source</dt>
                    <dd class="mt-0.5 font-medium text-foreground">
                      {source_label(imported.source)}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-muted-foreground">Redaction</dt>
                    <dd class="mt-0.5 font-medium text-foreground">
                      {imported.redaction_policy || "unknown"}
                    </dd>
                  </div>
                  <div class="col-span-2 md:col-span-4">
                    <dt class="text-muted-foreground">Fingerprint</dt>
                    <dd class="mt-0.5 truncate font-mono text-[10px] text-foreground">
                      {imported.payload_fingerprint || "unknown"}
                    </dd>
                  </div>
                </dl>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </section>
    """
  end

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end

  defp source_label(source) when is_map(source) do
    [source["product"], source["surface"], source["mode"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" / ")
    |> case do
      "" -> "unknown"
      label -> label
    end
  end

  defp source_label(_source), do: "unknown"
end
