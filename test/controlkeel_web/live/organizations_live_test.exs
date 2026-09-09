defmodule ControlKeelWeb.OrganizationsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Repo

  describe "local mode /organizations" do
    test "index lists every active org" do
      {:ok, _} = Accounts.create_org(%{name: "Alpha", slug: "alpha"})
      {:ok, _} = Accounts.create_org(%{name: "Beta", slug: "beta"})
      {:ok, _} = Accounts.create_org(%{name: "Gamma", slug: "gamma", status: "disabled"})

      {:ok, _view, html} = live(build_conn(), ~p"/organizations")

      assert html =~ "Organizations"
      assert html =~ "Alpha"
      assert html =~ "Beta"
      refute html =~ "Gamma"
    end

    test "index renders empty state when there are no orgs" do
      {:ok, _view, html} = live(build_conn(), ~p"/organizations")

      assert html =~ "No organizations yet."
    end

    test "local mode renders the org card with no role badge (role is nil)" do
      {:ok, _} = Accounts.create_org(%{name: "Local Co", slug: "local-co"})

      {:ok, view, html} = live(build_conn(), ~p"/organizations")

      # The org card is rendered.
      assert html =~ "Local Co"
      assert render(view) =~ "Local Co"

      # Local mode has no membership concept, so role is nil for every row and
      # the role badge component renders nothing. Assert on role-badge styling
      # rather than literal role text, since "member" also appears in the
      # "N members" count rendered on every card.
      refute render(view) =~ "ring-primary/20"
      refute render(view) =~ "ring-info/20"
    end

    test "new_org shows the local-mode info panel instead of the create form" do
      {:ok, view, html} = live(build_conn(), ~p"/organizations")

      # The New Organization button is still shown in local mode.
      assert html =~ "New Organization"
      assert html =~ "new_org"

      render_click(view, "new_org")

      html = render(view)
      assert html =~ "New organization"
      assert html =~ "Only the default organization is available in local mode"
      # The form is not rendered — only the info panel.
      refute html =~ ~s(id="organization-form")
    end

    test "cancel_new click closes the create modal" do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations")

      render_click(view, "new_org")
      assert render(view) =~ ~s(id="organization-create-modal")

      render_click(view, "cancel_new")
      refute render(view) =~ ~s(id="organization-create-modal")
    end

    test "save is denied in local mode and creates no org" do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations")

      html = render_submit(view, "save", %{"org" => %{name: "New Co", slug: "new-co"}})

      refute Repo.get_by(ControlKeel.Accounts.Org, slug: "new-co")
      assert html =~ "Organizations are not created in local mode"
    end
  end

  describe "cloud mode /organizations" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      {:ok, user} = Accounts.create_user(%{email: "cloud@example.com", name: "Cloud"})
      conn = build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

      {:ok, conn: conn, user: user}
    end

    test "index shows only the signed-in user's orgs", %{conn: conn, user: user} do
      {:ok, org} = Accounts.create_org_with_owner(user.id, %{name: "Mine", slug: "mine"})

      {:ok, other} = Accounts.create_user(%{email: "other@example.com"})
      {:ok, _} = Accounts.create_org_with_owner(other.id, %{name: "Theirs", slug: "theirs"})

      {:ok, _view, html} = live(conn, ~p"/organizations")

      assert html =~ "Mine"
      refute html =~ "Theirs"
      assert html =~ ~p"/organizations/#{org.slug}"
    end

    test "cloud mode renders the user's role per org row", %{conn: conn, user: user} do
      {:ok, _} = Accounts.create_org_with_owner(user.id, %{name: "Owned", slug: "owned"})

      {:ok, _view, html} = live(conn, ~p"/organizations")

      # The owner role badge is rendered for the user's org (not a placeholder).
      # Assert on the owner-specific styling and role text rather than a literal
      # `>owner<`, since HEEx renders the role text on its own line.
      assert html =~ "Owned"
      assert html =~ "ring-primary/20"
      assert html =~ "owner"
      refute html =~ "—"
    end

    test "save inserts an org plus an owner membership for the current user", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/organizations")
      render_click(view, "new_org")

      view
      |> form("#organization-form", org: %{name: "Cloud Co", slug: "cloud-co"})
      |> render_submit()

      org = Repo.get_by!(ControlKeel.Accounts.Org, slug: "cloud-co")

      membership = Accounts.get_active_membership(user.id, org.id)
      assert membership != nil
      assert membership.role == "owner"
    end

    test "index redirects to login when there is no signed-in user" do
      conn = build_conn() |> Plug.Test.init_test_session(%{})

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/organizations")
      assert to == "/auth/login"
    end
  end
end
