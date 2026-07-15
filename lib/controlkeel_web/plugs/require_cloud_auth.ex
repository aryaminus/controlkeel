defmodule ControlKeelWeb.Plugs.RequireCloudAuth do
  @moduledoc """
  Controller-side equivalent of `ControlKeelWeb.LiveAuth.require_cloud_auth`.

  Requires an active org membership (loaded by `LoadCurrentUser` into
  `conn.assigns[:current_membership]`) in cloud/self_hosted mode. In local mode
  it is a passthrough — single-user deployments have no memberships.

  On denial it halts with `401 JSON`, matching the API auth plug convention,
  since the routes it guards (e.g. observability export) are JSON endpoints.
  """

  import Plug.Conn

  alias ControlKeel.Runtime.Mode

  def init(opts), do: opts

  def call(conn, _opts) do
    if Mode.current() == :local do
      conn
    else
      if conn.assigns[:current_membership] do
        conn
      else
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "unauthorized"})
        |> halt()
      end
    end
  end
end
