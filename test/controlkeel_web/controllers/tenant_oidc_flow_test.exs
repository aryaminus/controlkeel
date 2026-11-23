defmodule ControlKeelWeb.TenantOIDCFlowTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.OrgIdentityProviders
  alias ControlKeelWeb.Endpoint
  alias ControlKeelWeb.OIDCTestHTTPAdapter

  setup do
    previous_adapter = Application.get_env(:assent, :http_adapter)
    previous_runtime_mode = Application.get_env(:controlkeel, :runtime_mode)

    Application.put_env(:assent, :http_adapter, OIDCTestHTTPAdapter)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      restore_env(:assent, :http_adapter, previous_adapter)
      restore_env(:controlkeel, :runtime_mode, previous_runtime_mode)
    end)

    n = System.unique_integer([:positive])
    {:ok, owner} = Accounts.create_user(%{email: "tenant-oidc-#{n}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{
        name: "Tenant OIDC #{n}",
        slug: "tenant-oidc-#{n}"
      })

    provider_attrs = %{
      "name" => "Example SSO",
      "issuer" => "https://idp.example",
      "client_id" => "client-abc",
      "client_secret" => "secret-abc",
      "scopes" => "openid email profile"
    }

    {:ok, provider} =
      OrgIdentityProviders.upsert(org.id, Map.put(provider_attrs, "slug", "example"))

    {:ok, other_owner} =
      Accounts.create_user(%{email: "other-tenant-oidc-#{n}@example.com"})

    {:ok, other_org} =
      Accounts.create_org_with_owner(other_owner.id, %{
        name: "Other Tenant OIDC #{n}",
        slug: "other-tenant-oidc-#{n}"
      })

    other_provider_attrs =
      provider_attrs
      |> Map.put("issuer", "https://other-idp.example")
      |> Map.put("client_id", "other-client")

    {:ok, other_provider} =
      OrgIdentityProviders.upsert(other_org.id, Map.put(other_provider_attrs, "slug", "example"))

    %{
      conn: Phoenix.ConnTest.build_conn(),
      org: org,
      provider: provider,
      other_org: other_org,
      other_provider: other_provider
    }
  end

  test "authorization request uses the adapter contract and persists state and tenant binding", %{
    conn: conn,
    org: org,
    provider: provider
  } do
    conn = get(conn, "/auth/oidc/#{org.slug}/#{provider.slug}/request")

    assert_receive {:oidc_http_request, :get,
                    "https://idp.example/.well-known/openid-configuration"}

    authorize_uri = URI.parse(redirected_to(conn, 302))
    params = URI.decode_query(authorize_uri.query)
    session_params = get_session(conn, :oidc_session_params)

    assert authorize_uri.path == "/authorize"

    assert params["redirect_uri"] ==
             Endpoint.url() <> "/auth/oidc/#{org.slug}/#{provider.slug}/callback"

    assert params["scope"] == "openid email profile"
    assert is_binary(params["state"])
    assert params["state"] == session_params.state
    assert params["nonce"] == session_params.nonce
    assert get_session(conn, :oidc_org_slug) == org.slug
    assert get_session(conn, :oidc_provider_slug) == provider.slug
  end

  test "duplicate provider slugs resolve under the requested organization", %{
    conn: conn,
    other_org: org,
    other_provider: provider
  } do
    conn = get(conn, "/auth/oidc/#{org.slug}/#{provider.slug}/request")

    assert_receive {:oidc_http_request, :get,
                    "https://other-idp.example/.well-known/openid-configuration"}

    authorize_uri = URI.parse(redirected_to(conn, 302))
    params = URI.decode_query(authorize_uri.query)

    assert authorize_uri.host == "other-idp.example"
    assert params["client_id"] == "other-client"

    assert params["redirect_uri"] ==
             Endpoint.url() <> "/auth/oidc/#{org.slug}/#{provider.slug}/callback"
  end

  test "callback rejects a state mismatch before token exchange", %{
    conn: conn,
    org: org,
    provider: provider
  } do
    conn = get(conn, "/auth/oidc/#{org.slug}/#{provider.slug}/request")
    assert_receive {:oidc_http_request, :get, _discovery_url}

    state = get_session(conn, :oidc_session_params).state

    conn =
      get(
        conn,
        "/auth/oidc/#{org.slug}/#{provider.slug}/callback?code=code&state=wrong-#{state}"
      )

    assert_receive {:oidc_http_request, :get, _discovery_url}
    refute_receive {:oidc_http_request, :post, _token_url}
    assert redirected_to(conn, 302) == "/auth/login"
    refute get_session(conn, :oidc_session_params)
    refute get_session(conn, :oidc_org_slug)
    refute get_session(conn, :oidc_provider_slug)
    refute get_session(conn, :current_user_id)
  end

  test "callback rejects another tenant using the same provider slug", %{
    conn: conn,
    org: org,
    provider: provider,
    other_org: other_org,
    other_provider: other_provider
  } do
    conn = get(conn, "/auth/oidc/#{org.slug}/#{provider.slug}/request")
    assert_receive {:oidc_http_request, :get, _discovery_url}
    state = get_session(conn, :oidc_session_params).state

    conn =
      get(
        conn,
        "/auth/oidc/#{other_org.slug}/#{other_provider.slug}/callback?code=code&state=#{URI.encode_www_form(state)}"
      )

    refute_receive {:oidc_http_request, _method, _url}
    assert redirected_to(conn, 302) == "/auth/login"
    refute get_session(conn, :oidc_session_params)
    refute get_session(conn, :oidc_org_slug)
    refute get_session(conn, :oidc_provider_slug)
    refute get_session(conn, :current_user_id)
  end

  test "callback without an initiating session fails closed", %{
    conn: conn,
    org: org,
    provider: provider
  } do
    conn = get(conn, "/auth/oidc/#{org.slug}/#{provider.slug}/callback?code=code&state=state")

    refute_receive {:oidc_http_request, _method, _url}
    assert redirected_to(conn, 302) == "/auth/login"
    refute get_session(conn, :current_user_id)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
