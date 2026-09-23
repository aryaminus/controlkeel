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

  @doc "Returns `:ok` or `{:error, :not_found}` using the same generic error for both gates."
  def authorize(session, current_user, org_slug, ws_slug) do
    cond do
      not ControlKeel.Accounts.session_accessible?(session, current_user) ->
        {:error, :not_found}

      check_scope(session, org_slug, ws_slug) != :ok ->
        {:error, :not_found}

      true ->
        :ok
    end
  end
end
