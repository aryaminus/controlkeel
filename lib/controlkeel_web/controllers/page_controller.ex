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
  alias ControlKeelWeb.FallbackController
  alias ControlKeelWeb.WorkspaceAccess

  # Public marketing pages render inside the `:public` framework layout
  # (ControlKeelWeb.Layouts). The layout reads @current_user/@flash directly,
  # so nothing needs to be forwarded from the templates.
  #
  # The root handoff is shared by local and signed-in cloud users. Anonymous
  # cloud visitors keep the marketing page.
  plug :put_layout, html: {ControlKeelWeb.Layouts, :public}

  def home(conn, _params) do
    cond do
      Mode.current() == :local ->
        {:ok, _defaults} = LocalDefaults.ensure()

        conn
        |> put_layout(false)
        |> render(:home,
          last_path_boot: true,
          fallback_path: latest_org_path(Accounts.list_orgs(status: "active"))
        )

      user = conn.assigns[:current_user] ->
        fallback_path =
          user.id
          |> Accounts.list_orgs_for_user()
          |> Enum.map(& &1.org)
          |> Enum.filter(&(&1.status == "active"))
          |> latest_org_path()

        conn
        |> put_layout(false)
        |> render(:home, last_path_boot: true, fallback_path: fallback_path)

      true ->
        render(conn, :home, last_path_boot: false, fallback_path: nil)
    end
  end

  defp latest_org_path(orgs) do
    case Enum.max_by(orgs, &{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id}, fn -> nil end) do
      %{slug: slug} -> "/#{slug}"
      nil -> ~p"/new/org"
    end
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

  # Legacy launcher URL (pre-/new/* rename): the session wizard now lives at
  # `/new/session`, which accepts the identical org_slug/ws_slug scoping
  # params, so the query string is preserved verbatim. Fixed same-origin
  # target, same shape as `org_legacy_redirect` above (issue #277).
  def session_start_legacy_redirect(conn, _params) do
    redirect(conn, to: "/new/session#{query_suffix(conn)}")
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

    case resolve_session_scope(id) do
      {:ok, {org_slug, ws_slug, session}} ->
        if timeline? do
          redirect(
            conn,
            to: "/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session.id}/activity"
          )
        else
          redirect(
            conn,
            to: "/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session.id}/observability#{anchor}"
          )
        end

      {:error, :not_found} ->
        FallbackController.not_found(conn, params)
    end
  end

  # Shared session-scope resolution for legacy redirects (session
  # observability URLs, proof browser URLs): maps a session id to its
  # org/workspace slugs plus the loaded session. Sessions without an
  # org-bound workspace fall back to the seeded local defaults in local
  # mode (single-user deployment) and 404 otherwise. Non-numeric ids 404
  # via `Integer.parse` instead of rescuing `Ecto.Query.CastError`.
  # Returns `{:ok, {org_slug, ws_slug, session}}` or
  # `{:error, :not_found}`. Callers own the access policy: some legacy
  # routes sit behind `:require_session_auth`, others enforce
  # `session_accessible?/2` themselves — the target LiveView re-enforces
  # access either way.
  defp resolve_session_scope(id) when is_integer(id) do
    case Repo.get(Session, id) do
      nil ->
        {:error, :not_found}

      %Session{} = session ->
        case Repo.preload(session, workspace: :org) do
          %{workspace: %Workspace{org: %{slug: org_slug}, slug: ws_slug}} ->
            {:ok, {org_slug, ws_slug, session}}

          _ ->
            if Runtime.local?() do
              {:ok,
               {LocalDefaults.default_org_slug(), LocalDefaults.default_workspace_slug(), session}}
            else
              {:error, :not_found}
            end
        end
    end
  end

  defp resolve_session_scope(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> resolve_session_scope(parsed)
      _ -> {:error, :not_found}
    end
  end

  defp resolve_session_scope(_), do: {:error, :not_found}

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
      nil -> default_member_workspace(user)
      ok -> ok
    end
  end

  # Brand-new cloud tenants may hold memberships but own zero sessions: land
  # them on their first org's first workspace instead of dead-ending on
  # /organizations (cloud analogue of the LocalDefaults fallback below). The
  # workspace comes from an org where the user holds an active membership, so
  # the target page's access check passes; nothing resolvable keeps the
  # /organizations outcome.
  defp default_member_workspace(user) do
    with org_id when is_integer(org_id) <- Accounts.default_org_for_user(user.id),
         [workspace | _] <- Mission.list_workspaces_for_orgs([org_id]),
         %{slug: ws_slug, org: %{slug: org_slug}} <- Repo.preload(workspace, :org) do
      {:ok, {org_slug, ws_slug}}
    else
      _ ->
        {:organizations, "No workspace available. Join or create an organization to continue."}
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

  # Legacy global proof browser URLs (pre-session-scope nesting): the index
  # and detail now live at
  # `/:org_slug/workspaces/:ws_slug/sessions/:id/proofs[/:proof_id]`.
  # These actions keep old bookmarks working by resolving the proof (or the
  # `session_id` query param) to its session's org/workspace slugs and 302ing
  # there, preserving the remaining query string. Like the observability
  # resolvers they must sit before the `:org_slug` live block so the
  # single-segment match does not swallow `/proofs`. Resolvers never render
  # data — unknown or inaccessible targets 404, and access is re-enforced by
  # the target LiveView.
  def proofs_redirect(%{path_params: %{"id" => id}} = conn, params) do
    case Integer.parse(id) do
      {proof_id, ""} ->
        case Mission.get_proof_bundle_with_context(proof_id) do
          nil ->
            FallbackController.not_found(conn, params)

          proof ->
            redirect_session_browser(conn, proof.session_id, params, "proofs", "/#{proof.id}", "")
        end

      _ ->
        FallbackController.not_found(conn, params)
    end
  end

  def proofs_redirect(conn, params) do
    case browser_session_id_param(params) do
      nil ->
        redirect_recent_session_browser(conn, params, "proofs")

      session_id ->
        redirect_session_browser(
          conn,
          session_id,
          params,
          "proofs",
          "",
          browser_query_suffix(conn)
        )
    end
  end

  # Legacy global findings browser URL (pre-session-scope nesting): the
  # index now lives at
  # `/:org_slug/workspaces/:ws_slug/sessions/:id/findings`. Same
  # auth-aware resolution as the proof browser above — the `session_id`
  # query param (or the most recent accessible session) decides the
  # target, remaining params are preserved. Single-segment, so it must
  # also sit before the `:org_slug` live block. The old page was
  # index-only, so there is no `:id` detail clause.
  def findings_redirect(conn, params) do
    case browser_session_id_param(params) do
      nil ->
        redirect_recent_session_browser(conn, params, "findings")

      session_id ->
        redirect_session_browser(
          conn,
          session_id,
          params,
          "findings",
          "",
          browser_query_suffix(conn)
        )
    end
  end

  defp redirect_session_browser(conn, session_id, params, page, suffix, query) do
    user = conn.assigns[:current_user]

    case resolve_session_scope(session_id) do
      {:ok, {org_slug, ws_slug, session}} ->
        # Local mode is single-user (`session_accessible?/2` is always
        # true there), so this check only bites in cloud mode — where the
        # local-defaults branch above already 404s.
        if Accounts.session_accessible?(session, user) do
          redirect(
            conn,
            to:
              "/#{org_slug}/workspaces/#{ws_slug}/sessions/#{session.id}/#{page}#{suffix}#{query}"
          )
        else
          FallbackController.not_found(conn, params)
        end

      {:error, :not_found} ->
        FallbackController.not_found(conn, params)
    end
  end

  defp redirect_recent_session_browser(conn, params, page) do
    user = conn.assigns[:current_user]

    if Mode.current() == :local do
      case Mission.list_recent_sessions(1) do
        [%Session{id: session_id} | _] ->
          redirect_session_browser(conn, session_id, params, page, "", browser_query_suffix(conn))

        [] ->
          case LocalDefaults.ensure() do
            {:ok, {%{slug: org_slug}, %{slug: ws_slug}}} ->
              redirect(conn, to: "/#{org_slug}/workspaces/#{ws_slug}")

            _ ->
              redirect(
                conn,
                to:
                  "/#{LocalDefaults.default_org_slug()}/workspaces/#{LocalDefaults.default_workspace_slug()}"
              )
          end
      end
    else
      cond do
        is_nil(user) ->
          redirect(conn, to: "/auth/login")

        not Accounts.any_active_membership?(user.id) ->
          conn
          |> put_flash(:info, "Join or create an organization to continue.")
          |> redirect(to: "/organizations")

        true ->
          case recent_accessible_browser_session(user) do
            nil ->
              conn
              |> put_flash(
                :info,
                "No workspace available. Join or create an organization to continue."
              )
              |> redirect(to: "/organizations")

            session ->
              redirect_session_browser(
                conn,
                session.id,
                params,
                page,
                "",
                browser_query_suffix(conn)
              )
          end
      end
    end
  end

  defp recent_accessible_browser_session(user) do
    user
    |> Mission.list_recent_sessions_for_user(10)
    |> Enum.find(&Accounts.session_accessible?(&1, user))
  end

  defp browser_session_id_param(params) do
    case params["session_id"] do
      nil ->
        nil

      value ->
        case Integer.parse(to_string(value)) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end
    end
  end

  defp browser_query_suffix(conn) do
    conn.query_params
    |> Map.delete("session_id")
    |> URI.encode_query()
    |> case do
      "" -> ""
      query -> "?#{query}"
    end
  end
end
