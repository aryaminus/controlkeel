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

  describe "login session shape and cross-org enforcement (issue #141, R5)" do
    import ControlKeel.MissionFixtures,
      only: [workspace_fixture: 1, session_fixture: 1]

    alias ControlKeel.Repo

    test "real callback session carries no org and still enforces cross-org denial", %{
      conn: conn
    } do
      # Drive the actual OAuth callback (mock provider): this is the session
      # shape production produces — user id only, never an org.
      login_conn =
        conn
        |> init_test_session(%{oauth_provider: "github", oauth_session_params: %{}})
        |> get("/auth/github/callback", %{"code" => "good"})

      assert redirected_to(login_conn, 302) == "/"

      user_id = get_session(login_conn, :current_user_id)
      assert is_integer(user_id)
      # Locks the production shape: nothing writes current_org_id at login.
      assert get_session(login_conn, :current_org_id) == nil

      user = Accounts.get_user(user_id)

      {:ok, org_a} =
        Accounts.create_org(%{
          name: "R5 Org A",
          slug: "r5a-#{System.unique_integer([:positive])}"
        })

      {:ok, org_b} =
        Accounts.create_org(%{
          name: "R5 Org B",
          slug: "r5b-#{System.unique_integer([:positive])}"
        })

      # Invite accepted after login: membership in org B only.
      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org_b.id,
        role: "viewer",
        status: "active"
      })
      |> Repo.insert!()

      session_a = session_fixture(%{workspace: workspace_fixture(%{org_id: org_a.id})})
      session_b = session_fixture(%{workspace: workspace_fixture(%{org_id: org_b.id})})

      # Replay exactly what the callback wrote — no hand-seeded org.
      authed =
        build_conn()
        |> Plug.Test.init_test_session(%{current_user_id: user_id})

      cross = get(authed, ~p"/observability/sessions/#{session_a.id}/export.json")
      assert json_response(cross, :not_found) == %{"error" => "session not found"}

      own = get(authed, ~p"/observability/sessions/#{session_b.id}/export.json")
      assert json_response(own, :ok)["integrity"]["session_id"] == session_b.id
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
