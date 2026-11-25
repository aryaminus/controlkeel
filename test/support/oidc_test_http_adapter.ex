defmodule ControlKeelWeb.OIDCTestHTTPAdapter do
  @moduledoc false

  @behaviour Assent.HTTPAdapter

  alias Assent.HTTPAdapter.HTTPResponse

  @impl Assent.HTTPAdapter
  def request(:get, url, _body, _headers, _opts) do
    send(self(), {:oidc_http_request, :get, url})
    issuer = String.replace_suffix(url, "/.well-known/openid-configuration", "")

    {:ok,
     %HTTPResponse{
       status: 200,
       headers: [{"content-type", "application/json"}],
       body: %{
         "issuer" => issuer,
         "authorization_endpoint" => issuer <> "/authorize",
         "token_endpoint" => issuer <> "/token",
         "jwks_uri" => issuer <> "/jwks"
       }
     }}
  end

  def request(method, url, _body, _headers, _opts) do
    send(self(), {:oidc_http_request, method, url})

    {:ok,
     %HTTPResponse{
       status: 500,
       headers: [{"content-type", "application/json"}],
       body: %{"error" => "unexpected request in OIDC security test"}
     }}
  end
end
