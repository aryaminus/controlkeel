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

  On success the page gets the organization context derived from its
  workspace (`:workspace`, `:nav_org`, `:nav_workspace`, `:breadcrumbs`) plus
  `:current_membership` — the membership the page was admitted with.
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

  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo
  alias ControlKeelWeb.OrgAccess
  alias ControlKeelWeb.ScopeError
  alias ControlKeelWeb.WorkspaceAccess

  @doc """
  Resolves the URL workspace, checks access, and assigns the shared chrome.

  `label` is the trailing breadcrumb ("Benchmark", "Trends", …), or `nil` for
  the workspace overview. Returns
  `{:error, socket}` with `:scope_error` assigned when the workspace is
  missing, belongs to another organization, or is not accessible to the
  visitor. The organization layout renders the in-place panel at the requested
  URL, so the visitor is not navigated away from the scope that failed.
  """
  @spec assign_scope(Phoenix.LiveView.Socket.t(), map(), String.t() | nil, String.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:error, Phoenix.LiveView.Socket.t()}
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
       |> assign(:scope_error, nil)
       |> assign(:workspace_scope, %{
         org_slug: workspace.org.slug,
         ws_slug: workspace.slug,
         label: label,
         required_role: required_role
       })}
    else
      {:error, reason} ->
        {:error, assign_scope_error(socket, params, reason, required_role)}
    end
  end

  @doc """
  Re-resolves the scope after `handle_params/3`.

  Returns `{:ok, socket, changed?}` when the URL still names an accessible
  workspace. `changed?` is `true` when the URL names a different workspace
  (or organization) than the one mounted, so the caller reloads its page
  data. Returns `{:error, socket}` with `:scope_error` assigned when the new
  URL is not accessible.
  """
  @spec refresh(Phoenix.LiveView.Socket.t(), map()) ::
          {:ok, Phoenix.LiveView.Socket.t(), boolean()} | {:error, Phoenix.LiveView.Socket.t()}
  def refresh(socket, params) do
    case socket.assigns[:workspace_scope] do
      %{org_slug: org_slug, ws_slug: ws_slug} = meta ->
        if params["org_slug"] == org_slug and params["ws_slug"] == ws_slug and
             is_nil(socket.assigns[:scope_error]) do
          {:ok, socket, false}
        else
          case assign_scope(socket, params, meta.label, meta.required_role) do
            {:ok, socket} -> {:ok, socket, true}
            {:error, socket} -> {:error, socket}
          end
        end

      _ ->
        # Nothing to re-resolve (the page already has a scope error).
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
      {:error, socket} -> {:noreply, socket}
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
    workspace_breadcrumb = %{
      label: workspace.name,
      to: if(is_nil(label), do: nil, else: "/#{workspace.org.slug}/workspaces/#{workspace.slug}")
    }

    [
      %{label: workspace.org.name, to: "/#{workspace.org.slug}"},
      workspace_breadcrumb
    ] ++ if(is_nil(label), do: [], else: [%{label: label, to: nil}])
  end

  defp assign_scope_error(socket, params, reason, _required_role) do
    kind =
      case reason do
        :forbidden -> :forbidden
        :needs_admin -> :needs_admin
        _ -> :not_found
      end

    case OrgAccess.resolve(params["org_slug"], socket.assigns[:current_user]) do
      {:ok, org, _membership} ->
        socket
        |> assign(:scope_error, ScopeError.workspace(params["org_slug"], params["ws_slug"], kind))
        |> assign(:nav_org, org)
        |> assign(:nav_workspace, nil)
        |> assign(:breadcrumbs, [%{label: org.name, to: "/#{org.slug}"}])

      {:error, org_error} ->
        socket
        |> assign(:scope_error, org_error)
        |> assign(:nav_org, nil)
        |> assign(:nav_workspace, nil)
        |> assign(:breadcrumbs, [])
    end
  end
end
