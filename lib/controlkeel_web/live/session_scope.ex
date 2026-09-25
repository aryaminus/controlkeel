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

  @doc """
  Loads the session context for a mount `id` param. Non-integer ids return
  `nil` (same as missing) instead of raising `Ecto.Query.CastError` in
  `Repo.get`, so `/sessions/abc` gets the generic not-found redirect.
  """
  def fetch_session(id) when is_integer(id), do: ControlKeel.Mission.get_session_context(id)

  def fetch_session(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> ControlKeel.Mission.get_session_context(int_id)
      _ -> nil
    end
  end

  def fetch_session(_), do: nil

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
        {:ok, session}
    end
  end

  @doc """
  Generic not-found redirect. Uses the same flash for missing, inaccessible,
  or scope-mismatched sessions to avoid existence disclosure.
  """
  def session_not_found(socket) do
    socket
    |> Phoenix.LiveView.put_flash(:error, "Session not found.")
    |> Phoenix.LiveView.push_navigate(to: "/")
  end
end
