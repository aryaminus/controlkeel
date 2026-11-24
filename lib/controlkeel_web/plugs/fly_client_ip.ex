defmodule ControlKeelWeb.Plugs.FlyClientIp do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = delete_req_header(conn, "x-fly-client-ip")

    case get_req_header(conn, "fly-client-ip") do
      [client_ip] -> put_req_header(conn, "x-fly-client-ip", client_ip)
      _ -> conn
    end
  end
end
