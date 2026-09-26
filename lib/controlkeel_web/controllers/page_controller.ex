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

  # Global benchmark entry point (pre-workspace-scope): the benchmark page now
  # lives at `/:org_slug/workspaces/:ws_slug/benchmark`. Resolve the visitor's
  # workspace and redirect; without a resolvable workspace fall back to the
  # workspace picker instead of a dead 404.
  def observability_benchmark_resolve(conn, _params) do
    query =
      case conn.query_string do
        "" -> ""
        query -> "?#{query}"
      end

    case benchmark_workspace(conn.assigns[:current_user]) do
      {org_slug, ws_slug} ->
        redirect(conn, to: "/#{org_slug}/workspaces/#{ws_slug}/benchmark#{query}")

      nil ->
        redirect(conn, to: ~p"/organizations")
    end
  end

  # Legacy observability benchmark sub-routes (pre-consolidation): the drafts,
  # scenarios, and history pages now live stacked in the workspace benchmark
  # page. Redirects preserve the query string and land on the matching section
  # anchor.
  def observability_benchmarks_redirect(conn, _params) do
    anchor =
      cond do
        String.ends_with?(conn.request_path, "/drafts") -> "#benchmarks-drafts"
        String.ends_with?(conn.request_path, "/scenarios") -> "#benchmarks-scenarios"
        String.ends_with?(conn.request_path, "/history") -> "#benchmarks-history"
        String.ends_with?(conn.request_path, "/regressions") -> "#benchmarks-regressions"
        true -> ""
      end

    query =
      case conn.query_string do
        "" -> ""
        query -> "?#{query}"
      end

    case benchmark_workspace(conn.assigns[:current_user]) do
      {org_slug, ws_slug} ->
        redirect(conn, to: "/#{org_slug}/workspaces/#{ws_slug}/benchmark#{anchor}#{query}")

      nil ->
        redirect(conn, to: ~p"/organizations")
    end
  end

  # Workspace resolution for the benchmark redirects: local mode uses the
  # seeded defaults; cloud/self_hosted uses the visitor's most recent
  # workspace (same heuristic the benchmark page previously mounted with).
  defp benchmark_workspace(user) do
    if Runtime.local?() do
      {LocalDefaults.default_org_slug(), LocalDefaults.default_workspace_slug()}
    else
      cloud_benchmark_workspace(user)
    end
  end

  defp cloud_benchmark_workspace(user) do
    case Mission.list_recent_sessions_for_user(user, 1) do
      [%{workspace: %{slug: ws_slug} = workspace} | _] ->
        case Repo.preload(workspace, :org) do
          %{org: %{slug: org_slug}} -> {org_slug, ws_slug}
          _ -> nil
        end

      [_ | _] ->
        nil

      _ ->
        nil
    end
  end
end
