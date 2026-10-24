defmodule ControlKeelWeb.SessionScope do
  @moduledoc """
  Shared session authorization helpers for session-scoped LiveViews.

  Centralizes the two gates required by `docs/plan-session-scoped-navigation-plan.md` slice 1:
  1. `session_accessible?` — the session must be accessible to `current_user`.
  2. Slug agreement — `org_slug`/`ws_slug` must match `session.workspace.org.slug`/`session.workspace.slug`.

  Both gates use the same generic `Session not found.` response to avoid existence disclosure.
  The slug check must run **after** the accessibility gate, which guarantees a loaded
  `workspace`/`org` (a nil/inaccessible session never reaches it).
  """

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Repo
  alias ControlKeelWeb.OrgAccess
  alias ControlKeelWeb.ScopeError
  alias ControlKeelWeb.WorkspaceAccess
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  @doc """
  Loads the session context for a mount `id` param. Non-integer ids return
  `nil` (same as missing) instead of raising `Ecto.Query.CastError` in
  `Repo.get`, so `/sessions/abc` gets the generic in-place not-found state.
  """
  def fetch_session(id) when is_integer(id), do: ControlKeel.Mission.get_session_context(id)

  def fetch_session(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> ControlKeel.Mission.get_session_context(int_id)
      _ -> nil
    end
  end

  def fetch_session(_), do: nil

  @doc """
  Resolves and authorizes a session against the URL scope.

  Successful session pages retain the workspace membership resolved from the
  session's organization so `LiveAuth` can react to revocation and role changes.
  """
  @spec resolve(Phoenix.LiveView.Socket.t(), map()) ::
          {:ok, map(), Phoenix.LiveView.Socket.t()} | {:error, Phoenix.LiveView.Socket.t()}
  def resolve(socket, %{
        "id" => id,
        "org_slug" => org_slug,
        "ws_slug" => ws_slug
      }) do
    case fetch_session(id) do
      nil ->
        {:error, socket}

      session ->
        with true <- Accounts.session_accessible?(session, socket.assigns[:current_user]),
             :ok <- check_scope(session, org_slug, ws_slug),
             {:ok, membership} <-
               WorkspaceAccess.check_membership(
                 session.workspace,
                 socket.assigns[:current_user]
               ) do
          {:ok, session, assign(socket, :current_membership, membership)}
        else
          _ -> {:error, socket}
        end
    end
  end

  def resolve(socket, _params), do: {:error, socket}

  @doc """
  Revalidates the session when a session-scoped LiveView handles new params.

  Returns whether the resolved session changed so pages can reset session-local
  assigns only when navigation switches to a different session.
  """
  @spec refresh(Phoenix.LiveView.Socket.t(), map()) ::
          {:ok, map(), Phoenix.LiveView.Socket.t(), boolean()}
          | {:error, Phoenix.LiveView.Socket.t()}
  def refresh(socket, params) do
    previous_session = socket.assigns[:session]

    case resolve(socket, params) do
      {:ok, session, socket} ->
        {:ok, session, socket, is_nil(previous_session) or previous_session.id != session.id}

      {:error, socket} ->
        {:error, socket}
    end
  end

  @doc "Returns `:ok` or `{:error, :workspace | :org}`."
  def check_scope(session, org_slug, ws_slug) do
    workspace = session.workspace
    org = workspace && workspace.org

    cond do
      is_nil(workspace) or workspace.slug != ws_slug -> {:error, :workspace}
      is_nil(org) or org.slug != org_slug -> {:error, :org}
      true -> :ok
    end
  end

  @doc """
  Re-validates an already-mounted session on refresh or post-mutation refetch.

  Runs the same two gates as mount (accessibility first, then slug agreement
  against the slugs stored in the socket's nav assigns). Returns
  `{:ok, session}` or `{:error, :not_found}` — callers must redirect with the
  generic "Session not found." flash so a revoked or deleted session stops
  receiving fresh data instead of polling indefinitely.
  """
  def reauthorize(socket, session) do
    current_user = socket.assigns[:current_user]
    org = socket.assigns[:nav_org]
    workspace = socket.assigns[:nav_workspace]

    cond do
      not ControlKeel.Accounts.session_accessible?(session, current_user) ->
        {:error, :not_found}

      is_nil(org) or is_nil(workspace) ->
        {:error, :not_found}

      check_scope(session, org.slug, workspace.slug) != :ok ->
        {:error, :not_found}

      true ->
        case WorkspaceAccess.check_membership(workspace, current_user) do
          {:ok, _membership} -> {:ok, session}
          {:error, _reason} -> {:error, :not_found}
        end
    end
  end

  @doc """
  Generic in-place not-found state for missing, inaccessible, or
  scope-mismatched sessions to avoid existence disclosure.
  """
  def session_not_found(socket, params \\ %{}) do
    socket = ensure_invalid_scope_event_guard(socket)

    org_slug = params["org_slug"] || get_in(socket.assigns, [:nav_org, Access.key(:slug)])
    ws_slug = params["ws_slug"] || get_in(socket.assigns, [:nav_workspace, Access.key(:slug)])
    session_id = params["id"] || get_in(socket.assigns, [:nav_session, Access.key(:id)])

    case OrgAccess.resolve(org_slug, socket.assigns[:current_user]) do
      {:ok, org, membership} ->
        case resolve_workspace(org, ws_slug, socket.assigns[:current_user]) do
          {:ok, workspace, workspace_membership} ->
            socket
            |> assign(:scope_error, ScopeError.session(org_slug, ws_slug, session_id))
            |> assign(:page_title, "Can't find the page")
            |> assign(:session, nil)
            |> assign(:nav_org, org)
            |> assign(:nav_workspace, workspace)
            |> assign(:nav_session, nil)
            |> assign(:current_membership, workspace_membership || membership)
            |> assign(:breadcrumbs, [
              %{label: org.name, to: "/#{org.slug}"},
              %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"}
            ])

          :error ->
            socket
            |> assign(:scope_error, ScopeError.workspace(org_slug, ws_slug))
            |> assign(:page_title, "Can't find the page")
            |> assign(:session, nil)
            |> assign(:nav_org, org)
            |> assign(:nav_workspace, nil)
            |> assign(:nav_session, nil)
            |> assign(:current_membership, membership)
            |> assign(:breadcrumbs, [%{label: org.name, to: "/#{org.slug}"}])
        end

      {:error, error} ->
        socket
        |> assign(:scope_error, error)
        |> assign(:page_title, error.title)
        |> assign(:session, nil)
        |> assign(:nav_org, nil)
        |> assign(:nav_workspace, nil)
        |> assign(:nav_session, nil)
        |> assign(:current_membership, nil)
        |> assign(:breadcrumbs, [])
    end
  end

  defp resolve_workspace(org, ws_slug, user) when is_binary(ws_slug) do
    case Mission.get_workspace_by_slug(ws_slug) do
      nil ->
        :error

      workspace ->
        workspace = Repo.preload(workspace, :org)

        if workspace.org_id == org.id and workspace.org.slug == org.slug do
          case WorkspaceAccess.check_membership(workspace, user) do
            {:ok, membership} -> {:ok, workspace, membership}
            {:error, _reason} -> :error
          end
        else
          :error
        end
    end
  end

  defp resolve_workspace(_org, _ws_slug, _user), do: :error

  defp ensure_invalid_scope_event_guard(
         %{assigns: %{session_scope_error_guard_attached: true}} = socket
       ),
       do: socket

  defp ensure_invalid_scope_event_guard(socket) do
    socket
    |> attach_hook(:session_scope_error_guard, :handle_event, &reject_invalid_scope_event/3)
    |> assign(:session_scope_error_guard_attached, true)
  end

  defp reject_invalid_scope_event(
         _event,
         _params,
         %{assigns: %{scope_error: error}} = socket
       )
       when not is_nil(error),
       do: {:halt, socket}

  defp reject_invalid_scope_event(_event, _params, socket), do: {:cont, socket}
end
