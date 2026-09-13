defmodule ControlKeelWeb.Plugs.LoadCurrentUser do
  @moduledoc """
  Loads the signed-in user and org membership from the browser session.

  When the session carries a user but no org (the production norm — issue
  #141), the first active membership's org is derived as the default and
  persisted back to the session. Downstream access gates must still resolve
  authority from (user, resource); this value is a default hint only.
  """

  import Plug.Conn

  alias ControlKeel.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if session_expired?(conn) do
      conn
      |> delete_session(:current_user_id)
      |> delete_session(:current_org_id)
      |> delete_session(:session_last_active)
      |> assign(:current_user, nil)
      |> assign(:current_org_id, nil)
      |> assign(:current_membership, nil)
    else
      user_id = get_session(conn, :current_user_id)
      org_id = get_session(conn, :current_org_id)

      user = if is_integer(user_id), do: Accounts.get_user(user_id)

      # Production never writes current_org_id (issue #141): when the
      # session carries no org, derive the default (first active
      # membership) and persist it so subsequent requests carry a real
      # value. Access decisions must not rely on this hint — the shared
      # gates resolve authority from (user, resource) instead.
      org_id =
        if is_nil(org_id) && user,
          do: Accounts.default_org_for_user(user.id),
          else: org_id

      {conn, org_id} =
        if org_id && is_nil(get_session(conn, :current_org_id)) do
          {put_session(conn, :current_org_id, org_id), org_id}
        else
          {conn, org_id}
        end

      membership =
        if user && is_integer(org_id), do: Accounts.get_active_membership(user.id, org_id)

      conn
      |> maybe_refresh_session_last_active(user)
      |> assign(:current_user, user)
      |> assign(:current_org_id, org_id)
      |> assign(:current_membership, membership)
    end
  end

  defp maybe_refresh_session_last_active(conn, nil), do: conn

  defp maybe_refresh_session_last_active(conn, _user) do
    put_session(conn, :session_last_active, DateTime.utc_now() |> DateTime.to_iso8601())
  end

  defp session_expired?(conn) do
    timeout = session_idle_timeout()

    if timeout > 0 do
      case get_session(conn, :session_last_active) do
        value when is_binary(value) ->
          case DateTime.from_iso8601(value) do
            {:ok, last_active, _offset} ->
              DateTime.diff(DateTime.utc_now(), last_active, :second) > timeout

            _ ->
              false
          end

        _ ->
          false
      end
    else
      false
    end
  end

  defp session_idle_timeout do
    case System.get_env("SESSION_IDLE_TIMEOUT_SECONDS", "0") do
      "" -> 0
      s -> String.to_integer(s)
    end
  end
end
