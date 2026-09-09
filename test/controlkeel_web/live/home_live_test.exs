defmodule ControlKeelWeb.HomeLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Repo

  describe "local mode /home" do
    test "index lists every active org" do
      {:ok, _} = Accounts.create_org(%{name: "Alpha", slug: "alpha"})
      {:ok, _} = Accounts.create_org(%{name: "Beta", slug: "beta"})
      {:ok, _} = Accounts.create_org(%{name: "Gamma", slug: "gamma", status: "disabled"})

      {:ok, _view, html} = live(build_conn(), ~p"/home")

      assert html =~ "Organizations"
      assert html =~ "Alpha"
      assert html =~ "Beta"
      refute html =~ "Gamma"
    end

    test "index renders empty state when there are no orgs" do
      {:ok, _view, html} = live(build_conn(), ~p"/home")

      assert html =~ "No organizations yet."
    end

    test "new_org shows the local-mode info panel instead of the create form" do
      {:ok, view, html} = live(build_conn(), ~p"/home")

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
      {:ok, view, _html} = live(build_conn(), ~p"/home")

      render_click(view, "new_org")
      assert render(view) =~ ~s(id="organization-create-modal")

      render_click(view, "cancel_new")
      refute render(view) =~ ~s(id="organization-create-modal")
    end

    test "save is denied in local mode and creates no org" do
      {:ok, view, _html} = live(build_conn(), ~p"/home")

      html = render_submit(view, "save", %{"org" => %{name: "New Co", slug: "new-co"}})

      refute Repo.get_by(ControlKeel.Accounts.Org, slug: "new-co")
      assert html =~ "Organizations are not created in local mode"
    end

    test "workspace rows link to the workspace page" do
      {:ok, org} = Accounts.create_org(%{name: "Alpha", slug: "alpha"})

      {:ok, ws} =
        ControlKeel.Mission.create_workspace(%{
          name: "Core",
          slug: "core",
          industry: "web",
          agent: "claude",
          budget_cents: 0,
          compliance_profile: "general",
          status: "active",
          org_id: org.id
        })

      {:ok, view, _html} = live(build_conn(), ~p"/home")

      view |> render_click("toggle_org", %{"org_id" => to_string(org.id)})

      assert render(view) =~
               ~s(href="/organizations/alpha/workspaces/#{ws.id}")
    end
  end

  describe "cloud mode /home" do
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

      {:ok, _view, html} = live(conn, ~p"/home")

      assert html =~ "Mine"
      refute html =~ "Theirs"
      assert html =~ ~p"/organizations/#{org.slug}"
    end

    test "cloud mode renders the user's org row", %{conn: conn, user: user} do
      {:ok, _} = Accounts.create_org_with_owner(user.id, %{name: "Owned", slug: "owned"})

      {:ok, _view, html} = live(conn, ~p"/home")

      assert html =~ "Owned"
      assert html =~ "workspaces"
    end

    test "save inserts an org plus an owner membership for the current user", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/home")
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

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/home")
      assert to == "/auth/login"
    end
  end
end
