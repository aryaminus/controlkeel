defmodule ControlKeelWeb.PageController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Accounts
  alias ControlKeel.Bootstrap.LocalDefaults
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Session
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo
  alias ControlKeel.Runtime
  alias ControlKeel.Runtime.Mode
  alias ControlKeel.Skills
  alias ControlKeelWeb.FallbackController
  alias ControlKeelWeb.WorkspaceAccess

  # Public marketing pages render inside the `:public` framework layout
  # (ControlKeelWeb.Layouts). The layout reads @current_user/@flash directly,
  # so nothing needs to be forwarded from the templates.
  plug :put_layout, html: {ControlKeelWeb.Layouts, :public}

  def home(conn, _params) do
    cond do
      # Local mode has no marketing surface — `/` goes straight to the
      # default org. ensure/0 is idempotent (find-or-create), so a fresh
      # local install provisions the org on first visit.
      Mode.current() == :local ->
        _ = LocalDefaults.ensure()
        redirect(conn, to: ~p"/#{LocalDefaults.default_org_slug()}")

      # Signed-in cloud/self_hosted users get their org → workspace →
      # session selector tree instead of the marketing landing.
      user = conn.assigns[:current_user] ->
        render(conn, :selector_tree, tree: selector_tree(user))

      true ->
        render(conn, :home)
    end
  end

  defp selector_tree(user) do
    orgs =
      user.id
      |> Accounts.list_orgs_for_user()
      |> Enum.map(& &1.org)
      |> Enum.sort_by(& &1.name)

    workspaces =
      orgs
      |> Enum.map(& &1.id)
      |> Mission.list_workspaces_for_orgs()

    sessions_by_workspace =
      workspaces
      |> Enum.map(& &1.id)
      |> Mission.list_sessions_for_workspaces()
      |> Enum.group_by(& &1.workspace_id)

    workspaces_by_org = Enum.group_by(workspaces, & &1.org_id)

    Enum.map(orgs, fn org ->
      workspaces =
        Enum.map(workspaces_by_org[org.id] || [], fn workspace ->
          %{workspace: workspace, sessions: sessions_by_workspace[workspace.id] || []}
        end)

      %{org: org, workspaces: workspaces}
    end)
  end

  def getting_started(conn, _params) do
    render(conn, :getting_started,
      install_channels: Skills.install_channels(),
      agent_integrations: Skills.agent_integrations()
    )
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def contact(conn, _params) do
    render(conn, :contact)
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def developers(conn, _params) do
    render(conn, :developers)
  end

  # Legacy /organizations/:slug URLs (removed when org routes were simplified
  # to /:slug). Single action serves both routes; the /settings suffix is
  # detected from the request path. `slug` is a single router segment (no
  # slashes), and the target is always same-origin via the "/#{slug}" prefix,
  # so this cannot become an open redirect.
  def org_legacy_redirect(conn, %{"slug" => slug}) do
    target =
      if String.ends_with?(conn.request_path, "/settings"),
        do: "/#{slug}/settings",
        else: "/#{slug}"

    redirect(conn, to: target)
  end

  # Legacy session observability URLs (pre-org-scope nesting): the
  # overview/memory tabs now live stacked at
  # `/:org_slug/workspaces/:ws_slug/sessions/:id/observability`.
  # Timeline lives canonically in `.../activity`. Resolves the numeric id
  # to its org/workspace slugs and redirects; memory preserves an anchor
  # so the stacked page scrolls there.
  def observability_session_redirect(conn, %{"id" => id} = params) do
    timeline? = String.ends_with?(conn.request_path, "/timeline")

    anchor =
      cond do
        timeline? -> ""
        String.ends_with?(conn.request_path, "/memory") -> "#session-observability-memory"
        true -> ""
      end

    case Repo.get(Session, id) do
      nil ->
        FallbackController.not_found(conn, params)

      %Session{} = session ->
        case Repo.preload(session, workspace: :org) do
          %{workspace: %Workspace{org: %{slug: org_slug}, slug: ws_slug}} ->
            if timeline? do
              redirect(
                conn,
                to: "/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session.id}/activity"
              )
            else
              redirect(
                conn,
                to:
                  "/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session.id}/observability#{anchor}"
              )
            end

          _ ->
            if Runtime.local?() do
              if timeline? do
                redirect(
                  conn,
                  to:
                    "/#{LocalDefaults.default_org_slug()}/workspaces/#{LocalDefaults.default_workspace_slug()}/sessions/#{session.id}/activity"
                )
              else
                redirect(
                  conn,
                  to:
                    "/#{LocalDefaults.default_org_slug()}/workspaces/#{LocalDefaults.default_workspace_slug()}/sessions/#{session.id}/observability#{anchor}"
                )
              end
            else
              FallbackController.not_found(conn, params)
            end
        end
    end
  rescue
    Ecto.Query.CastError -> ControlKeelWeb.FallbackController.not_found(conn, params)
  end

  # Global observability page URLs (pre-workspace-scope nesting): every
  # `/observability` and `/observability/<page>` path now lives at
  # `/:org_slug/workspaces/:ws_slug/observability/<page>`. These actions keep
  # old bookmarks and `controlkeel obs` flows working by resolving the
  # visitor's workspace and 302ing there with the query string preserved.
  # Resolution is workspace-first: the most recent session the visitor can
  # access decides, and the org is derived from that workspace so the pair
  # always agrees. Resolvers never render data — access is re-enforced by the
  # target LiveView.
  @observability_page_prefix "/observability"

  # Pre-consolidation aliases: these paths were never real pages, only
  # shortcuts into sections of the stacked benchmark page. They resolve
  # through the same workspace redirect, landing on the workspace benchmark
  # page (no section anchors, matching the old behavior).
  @legacy_benchmark_suffixes %{
    "/benchmarks/drafts" => "/benchmark",
    "/benchmarks/scenarios" => "/benchmark",
    "/benchmarks/history" => "/benchmark",
    "/regressions" => "/benchmark"
  }

  # Problems page removed: the aggregate counts live on the workspace
  # observability overview. This legacy-global URL keeps resolving there.
  def observability_problems_redirect(conn, _params) do
    redirect_observability(conn, "")
  end

  def observability_workspace_redirect(conn, _params) do
    suffix =
      conn.request_path
      |> String.replace_prefix(@observability_page_prefix, "")
      |> then(&Map.get(@legacy_benchmark_suffixes, &1, &1))

    redirect_observability(conn, suffix)
  end

  defp redirect_observability(conn, suffix) do
    case resolve_observability_workspace(conn) do
      {:ok, {org_slug, ws_slug}} ->
        redirect(
          conn,
          to: "/#{org_slug}/workspaces/#{ws_slug}/observability#{suffix}#{query_suffix(conn)}"
        )

      :login ->
        redirect(conn, to: "/auth/login")

      {:organizations, message} ->
        conn |> put_flash(:info, message) |> redirect(to: "/organizations")
    end
  end

  defp resolve_observability_workspace(conn) do
    user = conn.assigns[:current_user]

    if Mode.current() == :local do
      resolve_local_observability_workspace()
    else
      cond do
        is_nil(user) ->
          :login

        not Accounts.any_active_membership?(user.id) ->
          {:organizations, "Join or create an organization to continue."}

        true ->
          resolve_cloud_observability_workspace(user)
      end
    end
  end

  defp resolve_cloud_observability_workspace(user) do
    user
    |> Mission.list_recent_sessions_for_user(10)
    |> Enum.find_value(fn session ->
      case observability_workspace_slugs(session, user) do
        {:ok, _} = ok -> ok
        :skip -> nil
      end
    end)
    |> case do
      nil ->
        {:organizations, "No workspace available. Join or create an organization to continue."}

      ok ->
        ok
    end
  end

  defp resolve_local_observability_workspace do
    Mission.list_recent_sessions(10)
    |> Enum.find_value(fn session ->
      case observability_workspace_slugs(session, nil) do
        {:ok, _} = ok -> ok
        :skip -> nil
      end
    end)
    |> case do
      # Fresh local installs have no sessions yet: fall back to the seeded
      # default workspace rather than a picker (single-user deployment).
      nil -> default_observability_workspace()
      ok -> ok
    end
  end

  # A recent session votes for its workspace only when the workspace is
  # org-bound and the visitor can access it. The org slug is derived from the
  # workspace itself, so resolver output always satisfies the target page's
  # org/workspace agreement check.
  defp observability_workspace_slugs(session, user) do
    workspace = session.workspace && Repo.preload(session.workspace, :org)

    case workspace do
      %Workspace{slug: ws_slug, org: %{slug: org_slug}} ->
        if WorkspaceAccess.check(workspace, user) == :ok,
          do: {:ok, {org_slug, ws_slug}},
          else: :skip

      _ ->
        :skip
    end
  end

  defp default_observability_workspace do
    case LocalDefaults.ensure() do
      {:ok, {%{slug: org_slug}, %{slug: ws_slug}}} ->
        {:ok, {org_slug, ws_slug}}

      _ ->
        {:ok, {LocalDefaults.default_org_slug(), LocalDefaults.default_workspace_slug()}}
    end
  end

  defp query_suffix(conn) do
    case conn.query_string do
      "" -> ""
      query -> "?#{query}"
    end
  end
end
