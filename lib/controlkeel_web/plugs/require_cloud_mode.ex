defmodule ControlKeelWeb.Plugs.RequireCloudMode do
  @moduledoc """
  Redirects users away from routes that are not useful in the current mode.

  Three cases:
    * Already-signed-in users visiting `/auth/login` are redirected to `/`
      to avoid re-login loops (any mode).
    * In local mode (no OAuth/SSO), any `/auth/*` path is a dead end and
      redirects to `/` with an informational flash.
    * In local mode, `/invitations/*` paths are cloud-only features and
      redirect to `/`.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias ControlKeel.Runtime.Mode

  @auth_prefix "/auth/"
  @invitations_prefix "/invitations/"
  @login_path "/auth/login"

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      signed_in_visiting_login?(conn) ->
        conn
        |> redirect(to: "/")
        |> halt()

      local_mode_blocked_path?(conn) ->
        conn
        |> put_flash(:info, "This feature is not available in local mode.")
        |> redirect(to: "/")
        |> halt()

      true ->
        conn
    end
  end

  defp signed_in_visiting_login?(conn) do
    get_session(conn, :current_user_id) != nil and conn.request_path == @login_path
  end

  defp local_mode_blocked_path?(conn) do
    Mode.current() == :local and
      (String.starts_with?(conn.request_path, @auth_prefix) or
         String.starts_with?(conn.request_path, @invitations_prefix))
  end
end
