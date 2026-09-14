defmodule ControlKeelWeb.AuthControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts

  setup do
    original_runtime_mode = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      if is_nil(original_runtime_mode) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original_runtime_mode)
      end
    end)

    :ok
  end

  test "GET /auth/logout clears the session", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{
        current_user_id: 123,
        oauth_provider: "google",
        pending_invitation_token: "abc"
      })
      |> get("/auth/logout")

    assert redirected_to(conn, 302) == "/auth/login"
    refute get_session(conn, :current_user_id)
    refute get_session(conn, :oauth_provider)
    refute get_session(conn, :pending_invitation_token)
  end

  describe "GET /auth/org/:org_id (issue #141, R4)" do
    alias ControlKeel.Repo

    setup do
      {:ok, org_a} =
        Accounts.create_org(%{name: "Org A", slug: "sw-a-#{System.unique_integer([:positive])}"})

      {:ok, org_b} =
        Accounts.create_org(%{name: "Org B", slug: "sw-b-#{System.unique_integer([:positive])}"})

      {:ok, user} =
        Accounts.create_user(%{email: "sw-#{System.unique_integer([:positive])}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org_a.id,
        role: "member",
        status: "active"
      })
      |> Repo.insert!()

      {:ok, user: user, org_a: org_a, org_b: org_b}
    end

    defp switch_token(user_id, org_id) do
      Phoenix.Token.sign(ControlKeelWeb.Endpoint, "org-switch", %{
        user_id: user_id,
        org_id: org_id
      })
    end

    defp authed_conn(user_id) do
      build_conn() |> Plug.Test.init_test_session(%{current_user_id: user_id})
    end

    test "member with a valid token switches the default org", %{user: user, org_a: org} do
      token = switch_token(user.id, org.id)

      conn =
        authed_conn(user.id)
        |> get("/auth/org/#{org.id}?t=#{token}&return_to=/dashboard")

      assert redirected_to(conn, 302) == "/dashboard"
      assert get_session(conn, :current_org_id) == org.id
      assert get_session(conn, "phoenix_flash")["info"] == "Switched organization."
    end

    test "external return_to falls back to /organizations", %{user: user, org_a: org} do
      token = switch_token(user.id, org.id)

      conn =
        authed_conn(user.id)
        |> get("/auth/org/#{org.id}?t=#{token}&return_to=https://evil.example/phish")

      assert redirected_to(conn, 302) == "/organizations"
      assert get_session(conn, :current_org_id) == org.id
    end

    test "scheme-relative return_to is rejected", %{user: user, org_a: org} do
      token = switch_token(user.id, org.id)

      conn =
        authed_conn(user.id)
        |> get("/auth/org/#{org.id}?t=#{token}&return_to=//evil.example/phish")

      assert redirected_to(conn, 302) == "/organizations"
      assert get_session(conn, :current_org_id) == org.id
    end

    test "backslash return_to is rejected", %{user: user, org_a: org} do
      token = switch_token(user.id, org.id)

      conn =
        authed_conn(user.id)
        |> get("/auth/org/#{org.id}?t=#{token}&return_to=/\\evil.example/phish")

      assert redirected_to(conn, 302) == "/organizations"
      assert get_session(conn, :current_org_id) == org.id
    end

    test "encoded return_to bypass variants are rejected", %{user: user, org_a: org} do
      token = switch_token(user.id, org.id)

      conn =
        authed_conn(user.id)
        |> get("/auth/org/#{org.id}?t=#{token}&return_to=%2F%2Fevil.example/phish")

      assert redirected_to(conn, 302) == "/organizations"

      conn =
        authed_conn(user.id)
        |> get("/auth/org/#{org.id}?t=#{token}&return_to=%2F%5Cevil.example/phish")

      assert redirected_to(conn, 302) == "/organizations"
      assert get_session(conn, :current_org_id) == org.id
    end

    test "non-member org is refused without switching", %{user: user, org_a: default, org_b: org} do
      token = switch_token(user.id, org.id)

      conn =
        authed_conn(user.id)
        |> get("/auth/org/#{org.id}?t=#{token}")

      assert redirected_to(conn, 302) == "/organizations"

      assert get_session(conn, "phoenix_flash")["error"] ==
               "Organization not found or unavailable."

      # The derived default survives; the attacked org is never written.
      assert get_session(conn, :current_org_id) == default.id
    end

    test "token bound to another user is refused", %{user: user, org_a: org} do
      {:ok, other} =
        Accounts.create_user(%{email: "other-#{System.unique_integer([:positive])}@example.com"})

      token = switch_token(other.id, org.id)

      conn =
        authed_conn(user.id)
        |> get("/auth/org/#{org.id}?t=#{token}")

      assert redirected_to(conn, 302) == "/organizations"
      assert get_session(conn, :current_org_id) == org.id
    end

    test "path org differing from token org is refused", %{
      user: user,
      org_a: org_a,
      org_b: org_b
    } do
      token = switch_token(user.id, org_a.id)

      conn =
        authed_conn(user.id)
        |> get("/auth/org/#{org_b.id}?t=#{token}")

      assert redirected_to(conn, 302) == "/organizations"
      assert get_session(conn, :current_org_id) == org_a.id
    end

    test "garbage token is refused", %{user: user, org_a: org} do
      conn =
        authed_conn(user.id)
        |> get("/auth/org/#{org.id}?t=not-a-token")

      assert redirected_to(conn, 302) == "/organizations"
      assert get_session(conn, :current_org_id) == org.id
    end

    test "unauthenticated requests go to login", %{org_a: org} do
      conn = get(build_conn(), "/auth/org/#{org.id}?t=x")

      assert redirected_to(conn, 302) == "/auth/login"
    end
  end
end
