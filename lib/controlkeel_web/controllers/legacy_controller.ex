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

  alias ControlKeel.Bootstrap.LocalDefaults
  alias ControlKeel.Mission.Session
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

  def session(conn, %{"id" => id} = params) do
    case fetch_session_record(id) do
      nil ->
        FallbackController.not_found(conn, params)

      %Session{} = session ->
        case Repo.preload(session, workspace: :org) do
          %{workspace: %Workspace{org: %{slug: org_slug}, slug: ws_slug}} ->
            redirect_session(conn, params, org_slug, ws_slug, session.id)

          _ ->
            default_nesting_redirect(conn, params, session.id)
        end
    end
  end

  # Invariant: every session belongs to a workspace that belongs to an org
  # (local boot seeds the defaults; LocalMigration consolidates orphans).
  # If that ever doesn't hold, local mode degrades to the default nesting
  # instead of a dead 404 — the URL starts working once reconciliation binds
  # things. Cloud keeps the 404: no synthetic defaults there.
  defp default_nesting_redirect(conn, params, session_id) do
    if ControlKeel.Runtime.local?() do
      redirect_session(
        conn,
        params,
        LocalDefaults.default_org_slug(),
        LocalDefaults.default_workspace_slug(),
        session_id
      )
    else
      FallbackController.not_found(conn, params)
    end
  end

  defp redirect_session(conn, params, org_slug, ws_slug, session_id) do
    query =
      case conn.query_string do
        "" -> ""
        query -> "?#{query}"
      end

    redirect(
      conn,
      to:
        "/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session_id}#{session_subpath(params, conn)}#{query}"
    )
  end

  # The route is explicit per subpage (`/reviews`, `/deploy-review`,
  # `/reviews/:rid`), so the suffix is detected from the request path — same
  # approach as the workspace `/settings` suffix above.
  defp session_subpath(%{"rid" => rid}, _conn) when is_binary(rid), do: "/reviews/#{rid}"

  defp session_subpath(_params, conn) do
    cond do
      String.ends_with?(conn.request_path, "/reviews") -> "/reviews"
      String.ends_with?(conn.request_path, "/deploy-review") -> "/deploy-review"
      true -> ""
    end
  end

  # `Repo.get/2` raises on uncastable ids (e.g. `/workspaces/abc`); treat
  # those as unknown rather than a 400/500.
  defp fetch_workspace(id) do
    Repo.get(Workspace, id)
  rescue
    Ecto.Query.CastError -> nil
  end

  defp fetch_session_record(id) do
    Repo.get(Session, id)
  rescue
    Ecto.Query.CastError -> nil
  end
end
