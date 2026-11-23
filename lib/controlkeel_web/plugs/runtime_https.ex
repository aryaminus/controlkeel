defmodule ControlKeelWeb.Plugs.RuntimeHTTPS do
  @moduledoc """
  Runtime HTTPS policy helpers used by the production endpoint.
  """

  @doc """
  Returns whether an HTTP request should bypass the production HTTPS redirect.

  Local and self-hosted installs may explicitly serve HTTP. Cloud mode always
  requires HTTPS, even if `PHX_URL_SCHEME` is misconfigured.
  """
  def allow_http?(%Plug.Conn{scheme: :http}) do
    ControlKeel.Runtime.Mode.current() != :cloud and
      ControlKeel.Runtime.Defaults.endpoint_url_config()[:scheme] == "http"
  end

  def allow_http?(_conn), do: false
end
