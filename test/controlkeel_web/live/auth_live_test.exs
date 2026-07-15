defmodule ControlKeelWeb.AuthLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  defp put_oauth_env(providers) do
    prev = Application.get_env(:controlkeel, :oauth_providers)
    Application.put_env(:controlkeel, :oauth_providers, providers)
    on_exit(fn -> Application.put_env(:controlkeel, :oauth_providers, prev) end)
  end

  describe "render" do
    test "renders one button per configured provider", %{conn: conn} do
      put_oauth_env(
        google: [strategy: FakeStrategy, client_id: "id", client_secret: "secret"],
        github: [strategy: FakeStrategy, client_id: "id", client_secret: "secret"]
      )

      {:ok, _view, html} = live(conn, ~p"/auth/login")

      assert html =~ "Sign in with Google"
      assert html =~ "Sign in with GitHub"
      assert html =~ ~p"/auth/google/request"
      assert html =~ ~p"/auth/github/request"
    end

    test "renders a helpful empty state when no providers are configured", %{conn: conn} do
      put_oauth_env([])

      {:ok, _view, html} = live(conn, ~p"/auth/login")

      assert html =~ "No sign-in providers are configured"
      refute html =~ "Sign in with Google"
      refute html =~ "Sign in with GitHub"
    end
  end

  defmodule FakeStrategy do
    @moduledoc false
    def authorize_url(_),
      do: {:ok, %{url: "https://provider.example.com/auth", session_params: %{}}}

    def callback(_, _), do: {:ok, %{user: %{}, token: %{}}}
  end
end
