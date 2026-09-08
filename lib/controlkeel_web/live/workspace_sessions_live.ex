defmodule ControlKeelWeb.WorkspaceSessionsLive do
  @moduledoc """
  Sessions list for a workspace at `/organizations/:slug/workspaces/:id/sessions`.

  Moved off the workspace overview. Same access model as WorkspaceDetailLive:
  local mode open; cloud mode requires membership of the workspace's org.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(%{"id" => id, "slug" => slug} = _params, _session, socket) do
    with {ws_id, ""} <- Integer.parse(id),
         %Workspace{} = workspace <- Repo.get(Workspace, ws_id) |> Repo.preload(:org),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      sessions = Mission.list_all_sessions(ws_id)

      {:ok,
       socket
       |> assign(:page_title, "Sessions — #{workspace.name}")
       |> assign(:workspace, workspace)
       |> assign(:org, workspace.org)
       |> assign(
         :breadcrumbs,
         [
           %{label: "Organizations", to: ~p"/organizations"},
           %{label: workspace.org.name, to: ~p"/organizations/#{workspace.org.slug}"},
           %{
             label: workspace.name,
             to: ~p"/organizations/#{workspace.org.slug}/workspaces/#{workspace.id}"
           },
           %{label: "Sessions", to: nil}
         ]
       )
       |> assign(:sessions, sessions)}
    else
      :error ->
        {:ok, redirect_with_flash(socket, :error, "Invalid workspace id.", ~p"/organizations")}

      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-8">
      <div class="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
        <div class="space-y-2">
          <div class="flex items-center gap-2">
            <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
              Sessions
            </h1>
            <span class="rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
              {length(@sessions)} total
            </span>
          </div>
          <p class="text-sm text-muted-foreground">
            Sessions launched under {@workspace.name}.
          </p>
        </div>

        <.link
          navigate={~p"/sessions/start"}
          class="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition hover:bg-primary/90"
        >
          <.icon name="hero-plus" class="size-4" /> New Session
        </.link>
      </div>

      <div class="bg-card border rounded-2xl shadow-card max-h-[32rem] overflow-y-auto">
        <table class="min-w-full divide-y divide-border text-left text-sm">
          <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
            <tr>
              <th class="px-5 py-3 font-semibold">Session</th>
              <th class="px-5 py-3 font-semibold">Risk</th>
              <th class="px-5 py-3 font-semibold">Workload</th>
              <th class="px-5 py-3 font-semibold">Findings</th>
              <th class="px-5 py-3 font-semibold">Budget</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <%= if @sessions == [] do %>
              <tr>
                <td colspan="5" class="px-5 py-12 text-center">
                  <p class="text-base font-medium text-foreground">No sessions yet.</p>
                  <p class="mt-1 text-sm text-muted-foreground">
                    Sessions launched under this workspace will appear here.
                  </p>
                </td>
              </tr>
            <% else %>
              <%= for session <- @sessions do %>
                <tr class="transition hover:bg-muted/30">
                  <td class="max-w-sm px-5 py-4">
                    <.link
                      navigate={~p"/sessions/#{session.id}"}
                      class="font-medium text-foreground hover:underline"
                    >
                      {session.title}
                    </.link>
                  </td>
                  <td class="px-5 py-4">
                    <span class={[
                      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                      session.risk_tier in ["critical", "high"] &&
                        "bg-destructive/10 text-destructive ring-destructive/20",
                      session.risk_tier in ["medium", "moderate"] &&
                        "bg-warning/10 text-warning ring-warning/20",
                      session.risk_tier in ["low"] &&
                        "bg-success/10 text-success ring-success/20",
                      session.risk_tier not in ["critical", "high", "medium", "moderate", "low"] &&
                        "bg-muted text-muted-foreground ring-border"
                    ]}>
                      {session.risk_tier}
                    </span>
                  </td>
                  <td class="px-5 py-4">
                    <div class="flex items-center gap-2 text-muted-foreground">
                      <.icon name="hero-list-bullet" class="size-4 text-muted-foreground" />
                      {Enum.count(session.tasks)} tasks
                    </div>
                  </td>
                  <td class="px-5 py-4">
                    <div class="flex items-center gap-2 text-muted-foreground">
                      <.icon name="hero-exclamation-circle" class="size-4 text-muted-foreground" />
                      {Enum.count(session.findings)}
                    </div>
                  </td>
                  <td class="px-5 py-4 text-muted-foreground">
                    ${session.budget_cents |> Kernel./(100) |> trunc()}
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp check_org_slug(%Workspace{org_id: org_id}, %{slug: slug}) when is_integer(org_id) do
    case Accounts.get_org_by_slug(slug) do
      %Org{id: ^org_id} -> :ok
      _ -> {:error, "Workspace does not belong to this organization."}
    end
  end

  defp check_org_slug(_, _), do: {:error, "Workspace does not belong to this organization."}

  # Same view-access rules as WorkspaceDetailLive: local mode is open; cloud
  # mode requires membership of the workspace's org.
  defp check_workspace_access(workspace, assigns) do
    if Mode.current() == :local do
      :ok
    else
      check_cloud_workspace_access(workspace, assigns)
    end
  end

  defp check_cloud_workspace_access(%Workspace{org_id: nil}, _),
    do: {:error, "Workspace is not bound to an org."}

  defp check_cloud_workspace_access(%Workspace{org_id: ws_org}, %{current_org_id: org_id})
       when is_integer(ws_org) and ws_org == org_id,
       do: :ok

  defp check_cloud_workspace_access(_, _),
    do: {:error, "Workspace belongs to a different organization."}

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> put_flash(kind, msg)
    |> push_navigate(to: path)
  end
end
