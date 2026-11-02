defmodule ControlKeelWeb.WorkspaceScope do
  @moduledoc """
  Shared scope for workspace-scoped LiveViews mounted at
  `/:org_slug/workspaces/:ws_slug/...`.

  It replaces the per-view `check_org_slug/2` + `check_workspace_access/2`
  copies with one decision point:

    1. the workspace named by `ws_slug` must exist;
    2. the workspace must belong to the organization named by `org_slug`;
    3. the visitor must pass `ControlKeelWeb.WorkspaceAccess.check_membership/3`
       for that workspace's organization at the page's `required_role`.

  On success the page gets the org chrome it shares with every other
  workspace page (`:workspace`, `:nav_org`, `:nav_workspace`, `:breadcrumbs`)
  plus `:current_membership` — the membership the page was admitted with.
  Keeping that assign page-local is what lets `ControlKeelWeb.LiveAuth` evict
  the page when the membership is revoked and re-render permission-derived UI
  when the role changes.

  `refresh/2` re-runs the same gates when a patch changes `org_slug`/`ws_slug`
  on an already-mounted page. `push_patch/2` keeps the LiveView process alive,
  so without it a workspace switch would keep rendering the previous
  workspace's data — and the previous org's membership — under the new URL.
  To do that it reads back the `:workspace_scope` assign (`org_slug`, `ws_slug`,
  breadcrumb `label`, `required_role`) that mounting page recorded.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo
  alias ControlKeelWeb.WorkspaceAccess

  @organizations_path "/organizations"

  @doc """
  Resolves the URL workspace, checks access, and assigns the shared chrome.

  `label` is the trailing breadcrumb ("Benchmark", "Trends", …). Returns
  `{:redirect, socket}` with the error flash and navigation already applied
  when the workspace is missing, belongs to another organization, or is not
  accessible to the visitor.
  """
  @spec assign_scope(Phoenix.LiveView.Socket.t(), map(), String.t(), String.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:redirect, Phoenix.LiveView.Socket.t()}
  def assign_scope(socket, params, label, required_role \\ "viewer") do
    with {:ok, workspace} <- fetch_workspace(params),
         :ok <- check_org_slug(workspace, params["org_slug"]),
         {:ok, membership} <-
           WorkspaceAccess.check_membership(
             workspace,
             socket.assigns[:current_user],
             required_role
           ) do
      {:ok,
       socket
       |> assign(:workspace, workspace)
       |> assign(:nav_org, workspace.org)
       |> assign(:nav_workspace, workspace)
       |> assign(:current_membership, membership)
       |> assign(:breadcrumbs, breadcrumbs(workspace, label))
       |> assign(:workspace_scope, %{
         org_slug: workspace.org.slug,
         ws_slug: workspace.slug,
         label: label,
         required_role: required_role
       })}
    else
      {:error, reason} ->
        {:redirect, redirect_with_flash(socket, reason_message(reason, required_role))}
    end
  end

  @doc """
  Re-resolves the scope after `handle_params/3`.

  Returns `{:ok, socket, changed?}` when the URL still names an accessible
  workspace. `changed?` is `true` when the URL names a different workspace
  (or organization) than the one mounted, so the caller reloads its page
  data. Returns `{:redirect, socket}` when the new URL is not accessible.
  """
  @spec refresh(Phoenix.LiveView.Socket.t(), map()) ::
          {:ok, Phoenix.LiveView.Socket.t(), boolean()} | {:redirect, Phoenix.LiveView.Socket.t()}
  def refresh(socket, params) do
    case socket.assigns[:workspace_scope] do
      %{org_slug: org_slug, ws_slug: ws_slug} = meta ->
        if params["org_slug"] == org_slug and params["ws_slug"] == ws_slug do
          {:ok, socket, false}
        else
          case assign_scope(socket, params, meta.label, meta.required_role) do
            {:ok, socket} -> {:ok, socket, true}
            {:redirect, socket} -> {:redirect, socket}
          end
        end

      _ ->
        # Nothing to re-resolve (page is already redirecting).
        {:ok, socket, false}
    end
  end

  @doc """
  `handle_params/3` body for pages whose only URL parameters are the scope
  slugs: reloads page data only when the workspace changed.
  """
  @spec on_params(Phoenix.LiveView.Socket.t(), map(), (Phoenix.LiveView.Socket.t(), map() ->
                                                         Phoenix.LiveView.Socket.t())) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def on_params(socket, params, reload) do
    case refresh(socket, params) do
      {:ok, socket, true} -> {:noreply, reload.(socket, params)}
      {:ok, socket, false} -> {:noreply, socket}
      {:redirect, socket} -> {:noreply, socket}
    end
  end

  defp fetch_workspace(%{"ws_slug" => ws_slug}) when is_binary(ws_slug) do
    case Mission.get_workspace_by_slug(ws_slug) do
      %Workspace{} = workspace -> {:ok, Repo.preload(workspace, :org)}
      nil -> {:error, :not_found}
    end
  end

  defp fetch_workspace(_params), do: {:error, :not_found}

  defp check_org_slug(%Workspace{org: %{slug: slug}}, slug), do: :ok
  defp check_org_slug(_workspace, _slug), do: {:error, :wrong_org}

  defp breadcrumbs(workspace, label) do
    [
      %{label: workspace.org.name, to: "/#{workspace.org.slug}"},
      %{label: workspace.name, to: "/#{workspace.org.slug}/workspaces/#{workspace.slug}"},
      %{label: label, to: nil}
    ]
  end

  defp redirect_with_flash(socket, message) do
    socket
    |> put_flash(:error, message)
    |> push_navigate(to: @organizations_path)
  end

  defp reason_message(:not_found, _required_role), do: "Workspace not found."

  defp reason_message(:wrong_org, _required_role),
    do: "Workspace does not belong to this organization."

  defp reason_message(:unbound, _required_role), do: "Workspace is not bound to an org."

  defp reason_message(:forbidden, _required_role),
    do: "Workspace belongs to a different organization."

  # Unreachable for read surfaces (`required_role` is "viewer"), kept for the
  # admin surfaces that adopt this module.
  defp reason_message(:needs_admin, "viewer"), do: "This workspace requires an active membership."
  defp reason_message(:needs_admin, _required_role), do: "Admin or owner role required."
end
