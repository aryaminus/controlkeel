defmodule ControlKeelWeb.OAuthLoginControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts

  setup do
    original_adapter = Application.get_env(:controlkeel, :oauth_provider_adapter)
    original_oauth_config = Application.get_env(:controlkeel, :oauth_providers)
    original_runtime_mode = Application.get_env(:controlkeel, :runtime_mode)

    Application.put_env(
      :controlkeel,
      :oauth_provider_adapter,
      ControlKeelWeb.OAuthLoginControllerTest.TestOAuthProviderAdapter
    )

    Application.put_env(:controlkeel, :oauth_providers,
      github: [client_id: "test-client", client_secret: "test-secret"],
      google: [client_id: "test-client", client_secret: "test-secret"]
    )

    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      if is_nil(original_adapter) do
        Application.delete_env(:controlkeel, :oauth_provider_adapter)
      else
        Application.put_env(:controlkeel, :oauth_provider_adapter, original_adapter)
      end

      if is_nil(original_oauth_config) do
        Application.delete_env(:controlkeel, :oauth_providers)
      else
        Application.put_env(:controlkeel, :oauth_providers, original_oauth_config)
      end

      if is_nil(original_runtime_mode) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original_runtime_mode)
      end
    end)

    :ok
  end

  describe "GET /auth/:provider/request" do
    test "redirects to the provider and stores OAuth session data", %{conn: conn} do
      conn = get(conn, "/auth/github/request")

      assert redirected_to(conn, 302) == "https://example.com/auth"
      assert get_session(conn, :oauth_provider) == "github"
      assert get_session(conn, :oauth_session_params) == %{state: "abc"}
    end

    test "flashes an error when the provider is not configured", %{conn: conn} do
      Application.delete_env(:controlkeel, :oauth_providers)

      conn = get(conn, "/auth/github/request")

      assert redirected_to(conn, 302) == "/auth/login"

      assert get_session(conn, "phoenix_flash")["error"] ==
               "Sign-in with github is not configured."
    end

    test "flashes an error when the provider is unsupported", %{conn: conn} do
      conn = get(conn, "/auth/unknown/request")

      assert redirected_to(conn, 302) == "/auth/login"

      assert get_session(conn, "phoenix_flash")["error"] ==
               "Failed to start sign-in. Please try again."
    end
  end

  describe "GET /auth/:provider/callback" do
    test "provisions the user and shows a success flash", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{oauth_provider: "github", oauth_session_params: %{}})
        |> get("/auth/github/callback", %{"code" => "good"})

      assert redirected_to(conn, 302) == "/"
      assert get_session(conn, "phoenix_flash")["info"] == "Signed in with GitHub."
      assert Accounts.get_user_by_email("user@example.com")
      assert get_session(conn, :current_user_id)
      refute get_session(conn, :oauth_provider)
      refute get_session(conn, :oauth_session_params)
    end

    test "flashes an error and clears OAuth session state on callback failure", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{oauth_provider: "github", oauth_session_params: %{state: "abc"}})
        |> get("/auth/github/callback", %{"code" => "bad"})

      assert redirected_to(conn, 302) == "/auth/login"

      assert get_session(conn, "phoenix_flash")["error"] ==
               "Provider did not return an email address."

      refute get_session(conn, :oauth_provider)
      refute get_session(conn, :oauth_session_params)
    end
  end

  defmodule TestOAuthProviderAdapter do
    @behaviour ControlKeel.Accounts.OAuthProviders

    def authorize_url(_provider, _cfg, _opts) do
      {:ok, %{url: "https://example.com/auth", session_params: %{state: "abc"}}}
    end

    def callback(:github, _cfg, %{"code" => "bad"}, _opts) do
      {:error, :missing_email}
    end

    def callback(:github, _cfg, _params, _opts) do
      {:ok, %{email: "user@example.com", name: "Example User"}}
    end

    def callback(:google, _cfg, _params, _opts) do
      {:ok, %{email: "user@example.com", name: "Example User"}}
    end
  end
end
