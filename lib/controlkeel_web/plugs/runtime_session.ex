defmodule ControlKeelWeb.Plugs.RuntimeSession do
  @moduledoc """
  Configures the session cookie's `Secure` attribute from the request scheme.

  Release binaries run with `MIX_ENV=prod` even in local mode, so the cookie
  attribute cannot be selected from compile-time environment configuration.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: Plug.Session.init(opts)

  @impl Plug
  def call(%Plug.Conn{scheme: scheme} = conn, config) do
    cookie_opts =
      case scheme do
        :https -> Keyword.put(config.cookie_opts, :secure, true)
        _ -> Keyword.delete(config.cookie_opts, :secure)
      end

    Plug.Session.call(conn, %{config | cookie_opts: cookie_opts})
  end
end
