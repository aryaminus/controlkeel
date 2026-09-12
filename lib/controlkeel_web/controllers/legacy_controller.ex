defmodule ControlKeelWeb.LegacyController do
  @moduledoc """
  Redirects for pre-consolidation workspace URLs.

  Detail/settings lived under `/organizations/:slug/workspaces/:id*` and the
  tab pages under `/workspaces/:id/*`. Both shapes now live under
  `/:org_slug/workspaces/:ws_slug/*`, so resolve the numeric id (preloading
  the workspace's org — the `:slug` in the old URL may be stale) and redirect
  to the slug-based URL. Unknown ids or subpaths 404, mirroring the old
  routes which had no match for them.
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo
  alias ControlKeelWeb.FallbackController

  # Valid workspace subpages, then and now.
  @subpaths ~w(settings repos service-accounts webhooks tool-policy)

  def workspace(conn, %{"id" => id} = params) do
    with %Workspace{} = workspace <- fetch_workspace(id),
         workspace = Repo.preload(workspace, :org),
         {:ok, suffix} <- subpath(params, conn) do
      redirect(conn, to: "/#{workspace.org.slug}/workspaces/#{workspace.slug}#{suffix}")
    else
      _ -> FallbackController.not_found(conn, params)
    end
  end

  # `/workspaces/:id/*rest` carries the subpage as a glob; anything outside
  # the known pages 404s. The `/organizations/...` shapes have no glob, so
  # the only valid suffix there is `/settings`, detected from the path.
  defp subpath(%{"rest" => []}, _conn), do: {:ok, ""}
  defp subpath(%{"rest" => [page]}, _conn) when page in @subpaths, do: {:ok, "/#{page}"}
  defp subpath(%{"rest" => _}, _conn), do: :error

  defp subpath(_params, conn) do
    if String.ends_with?(conn.request_path, "/settings"),
      do: {:ok, "/settings"},
      else: {:ok, ""}
  end

  # `Repo.get/2` raises on uncastable ids (e.g. `/workspaces/abc`); treat
  # those as unknown rather than a 400/500.
  defp fetch_workspace(id) do
    Repo.get(Workspace, id)
  rescue
    Ecto.Query.CastError -> nil
  end
end
