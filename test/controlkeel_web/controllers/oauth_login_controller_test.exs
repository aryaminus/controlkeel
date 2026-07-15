defmodule ControlKeelWeb.OAuthLoginControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  defmodule FakeStrategy do
    @moduledoc false
    def authorize_url(_config) do
      {:ok, %{url: "https://provider.example.com/auth", session_params: %{state: "test-state"}}}
    end

    def callback(_config, _params) do
      {:ok,
       %{
         user: %{
           "sub" => "fake-uid",
           "email" => "oauth-user@example.com",
           "email_verified" => true,
           "name" => "OAuth User",
           "picture" => "https://example.com/avatar.png"
         },
         token: %{}
       }}
    end
  end

  defmodule FailingStrategy do
    @moduledoc false
    def authorize_url(_config) do
      {:ok, %{url: "https://provider.example.com/auth", session_params: %{state: "x"}}}
    end

    def callback(_config, _params), do: {:error, :invalid_code}
  end

  defp put_oauth_env(providers) do
    prev = Application.get_env(:controlkeel, :oauth_providers)
    Application.put_env(:controlkeel, :oauth_providers, providers)
    on_exit(fn -> Application.put_env(:controlkeel, :oauth_providers, prev) end)
  end

  describe "request/2" do
    test "redirects to the provider authorize URL and stores oauth session params", %{conn: conn} do
      put_oauth_env(google: [strategy: FakeStrategy, client_id: "id", client_secret: "secret"])

      conn = get(conn, ~p"/auth/google/request")

      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["https://provider.example.com/auth"]
      assert get_session(conn, :oauth_session_params) == %{state: "test-state"}
      assert get_session(conn, :oauth_provider) == "google"
    end

    test "redirects to login when the provider is not configured", %{conn: conn} do
      put_oauth_env([])
      conn = get(conn, ~p"/auth/google/request")
      assert redirected_to(conn) == ~p"/auth/login"
    end

    test "redirects to login for an unknown provider name", %{conn: conn} do
      put_oauth_env(google: [strategy: FakeStrategy])
      conn = get(conn, ~p"/auth/notarealprovider/request")
      assert redirected_to(conn) == ~p"/auth/login"
    end
  end

  describe "callback/2" do
    test "establishes the session and redirects on success", %{conn: conn} do
      put_oauth_env(google: [strategy: FakeStrategy, client_id: "id", client_secret: "secret"])

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          oauth_provider: "google",
          oauth_session_params: %{state: "test-state"}
        })
        |> get(~p"/auth/google/callback?code=abc&state=test-state")

      assert conn.status == 302
      assert redirected_to(conn) == ~p"/cloud/projects"
      assert get_session(conn, :current_user_id) != nil
      assert get_session(conn, :session_last_active) != nil
      assert get_session(conn, :oauth_session_params) == nil
      assert get_session(conn, :oauth_provider) == nil
    end

    test "clears oauth session and redirects to login on provider error", %{conn: conn} do
      put_oauth_env(google: [strategy: FailingStrategy, client_id: "id", client_secret: "secret"])

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          oauth_provider: "google",
          oauth_session_params: %{state: "x"}
        })
        |> get(~p"/auth/google/callback?code=bad&state=x")

      assert redirected_to(conn) == ~p"/auth/login"
      assert get_session(conn, :oauth_session_params) == nil
      assert get_session(conn, :oauth_provider) == nil
    end

    test "redirects to login when no oauth provider is in the session", %{conn: conn} do
      put_oauth_env(google: [strategy: FakeStrategy])

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get(~p"/auth/google/callback?code=abc")

      assert redirected_to(conn) == ~p"/auth/login"
    end
  end
end
