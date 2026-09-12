defmodule ControlKeelWeb.Plugs.RequireSessionAuth do
  @moduledoc """
  Controller-side counterpart of `LiveAuth.require_cloud_auth` for
  session-scoped, non-LiveView routes (issue #123 item 4a, CK-AUTH-001).

  Semantics mirror the LiveView on_mount hook:

    * **local mode** — passthrough (no user model exists locally).
    * **cloud/self_hosted mode** — requires a signed-in user
      (`conn.assigns.current_user`, loaded by `LoadCurrentUser`); otherwise
      halts with `401` JSON.

  When the request path carries a session `id` param, the plug additionally
  resolves that ControlKeel session and enforces org ownership through the
  shared `Accounts.session_accessible?/2` gate: a missing session or a
  session whose workspace belongs to another org halts with `404` JSON
  (existence is not leaked). Routes without an `id` path param only get the
  authentication check.

  Expected to run inside the `:browser` pipeline so `LoadCurrentUser` has
  already populated `current_user`.
  Org scoping is resolved per-URL, not from session.
  """

  import Plug.Conn
  alias ControlKeel.Mission
  alias ControlKeel.Runtime.Mode

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Mode.current() == :local do
      conn
    else
      conn
      |> require_user()
      |> authorize_session_access()
    end
  end

  defp require_user(%{assigns: %{current_user: %{} = _user}} = conn), do: conn

  defp require_user(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:unauthorized, Jason.encode!(%{error: "sign in required"}))
    |> halt()
  end

  defp authorize_session_access(conn) do
    case session_id(conn) do
      nil ->
        conn

      id ->
        case resolve_session(id) do
          nil -> not_found(conn)
          session -> check_org_access(conn, session)
        end
    end
  end

  defp session_id(conn) do
    case Map.get(conn.path_params, "id") do
      binary when is_binary(binary) ->
        case Integer.parse(binary) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end

      other ->
        other
    end
  end

  defp resolve_session(id) when is_integer(id), do: Mission.get_session_context(id)
  defp resolve_session(_id), do: nil

  defp check_org_access(conn, _session) do
    conn
  end

  defp not_found(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:not_found, Jason.encode!(%{error: "session not found"}))
    |> halt()
  end
end
