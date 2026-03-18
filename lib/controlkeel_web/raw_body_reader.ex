defmodule ControlKeelWeb.RawBodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    read_body(conn, opts, [])
  end

  defp read_body(conn, opts, acc) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        full_body = IO.iodata_to_binary(Enum.reverse([body | acc]))
        {:ok, full_body, put_in(conn.private[:raw_body], full_body)}

      {:more, body, conn} ->
        read_body(conn, opts, [body | acc])
    end
  end
end
