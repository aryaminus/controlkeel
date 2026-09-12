defmodule ControlKeelWeb.Plugs.LoadCurrentUser do
  @moduledoc "Loads the signed-in user from the browser session."

  import Plug.Conn

  alias ControlKeel.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if session_expired?(conn) do
      conn
      |> delete_session(:current_user_id)
      |> delete_session(:session_last_active)
      |> assign(:current_user, nil)
    else
      user_id = get_session(conn, :current_user_id)

      user = if is_integer(user_id), do: Accounts.get_user(user_id)

      conn
      |> maybe_refresh_session_last_active(user)
      |> assign(:current_user, user)
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
