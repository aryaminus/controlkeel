defmodule ControlKeelWeb.CloudOnboardingLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts

  setup do
    {:ok, user} = Accounts.create_user(%{email: "new@example.com", name: "New User"})
    {:ok, user: user}
  end

  defp authed_conn(conn, user) do
    Plug.Test.init_test_session(conn, %{current_user_id: user.id})
  end

  test "renders the org-name form for a signed-in user", %{conn: conn, user: user} do
    {:ok, _view, html} = live(authed_conn(conn, user), ~p"/cloud/onboarding")

    assert html =~ "Set up your workspace"
    assert html =~ "Organization name"
  end

  test "creates a personal org and hands off to the completion flow", %{conn: conn, user: user} do
    {:ok, view, _html} = live(authed_conn(conn, user), ~p"/cloud/onboarding")

    view
    |> form("#onboarding-form", %{"name" => "Acme"})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r"/auth/complete/"

    [membership] = Accounts.list_memberships_for_user(user.id, status: "active")
    assert membership.role == "owner"
    assert Accounts.get_org_by_slug("acme")
  end

  test "shows an error for an empty name", %{conn: conn, user: user} do
    {:ok, view, _html} = live(authed_conn(conn, user), ~p"/cloud/onboarding")

    html =
      view
      |> form("#onboarding-form", %{"name" => "  "})
      |> render_submit()

    assert html =~ "Enter a name for your workspace"
    assert Accounts.list_memberships_for_user(user.id, status: "active") == []
  end
end
