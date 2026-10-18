defmodule ControlKeelWeb.NewOrgLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.AccountsFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Repo

  describe "local mode /new/org" do
    test "renders the local-mode info panel instead of the create form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/new/org")

      assert html =~ "Create an organization"
      assert html =~ "Only the default organization is available in local mode"
      refute html =~ ~s(id="new-org-form")
    end

    test "save is denied in local mode and creates no org", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new/org")

      html = render_submit(view, "save", %{"org" => %{name: "New Co", slug: "new-co"}})

      refute Repo.get_by(Org, slug: "new-co")
      assert html =~ "Organizations are not created in local mode"
    end
  end

  describe "cloud mode /new/org" do
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

      :ok
    end

    defp cloud_conn(user, org_id \\ nil) do
      build_conn()
      |> Plug.Test.init_test_session(%{
        "current_user_id" => user.id,
        "current_org_id" => org_id
      })
    end

    test "renders the create form for a signed-in membered user", %{} do
      user = user_fixture()
      {:ok, _org} = Accounts.create_org_with_owner(user.id, %{name: "Existing", slug: "existing"})

      {:ok, _view, html} = live(cloud_conn(user), ~p"/new/org")

      assert html =~ "Create an organization"
      assert html =~ ~s(id="new-org-form")
    end

    test "memberless user can reach /new/org (gate exemption)", %{} do
      user = user_fixture()

      {:ok, view, html} = live(cloud_conn(user), ~p"/new/org")

      assert html =~ ~s(id="new-org-form")
      assert has_element?(view, "#new-org-form input[name=\"org[name]\"]")
    end

    test "back button is disabled for a memberless first-run user", %{} do
      user = user_fixture()

      {:ok, view, _html} = live(cloud_conn(user), ~p"/new/org")

      # No org to go back to: the top bar renders the disabled affordance
      # instead of the "/" back link, so Back cannot loop through the handoff.
      assert has_element?(view, ~s(span[aria-disabled="true"]))
      refute has_element?(view, ~s(a[href="/"]))
    end

    test "back button is enabled once the user has an org", %{} do
      user = user_fixture()
      {:ok, _org} = Accounts.create_org_with_owner(user.id, %{name: "Has Org", slug: "has-org"})

      {:ok, view, _html} = live(cloud_conn(user), ~p"/new/org")

      assert has_element?(view, ~s(a[href="/"]))
      refute has_element?(view, ~s(span[aria-disabled="true"]))
    end

    test "signed-out user is redirected to login", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})

      assert {:error, {:redirect, %{to: "/auth/login"}}} = live(conn, ~p"/new/org")
    end

    test "save creates an org plus an owner membership and navigates to the new org", %{} do
      user = user_fixture()
      {:ok, view, _html} = live(cloud_conn(user), ~p"/new/org")

      view
      |> form("#new-org-form", org: %{name: "Cloud Co", slug: "cloud-co"})
      |> render_submit()

      org = Repo.get_by!(Org, slug: "cloud-co")

      membership = Accounts.get_active_membership(user.id, org.id)
      assert membership != nil
      assert membership.role == "owner"

      assert {"/cloud-co", flash} = assert_redirect(view)
      assert flash["info"] =~ "Cloud Co"
    end

    test "save with the default workspace box checked creates a starter workspace", %{} do
      user = user_fixture()
      {:ok, view, _html} = live(cloud_conn(user), ~p"/new/org")

      view
      |> form("#new-org-form",
        org: %{
          name: "With WS",
          slug: "with-ws",
          create_default_workspace: "true"
        }
      )
      |> render_submit()

      org = Repo.get_by!(Org, slug: "with-ws")
      assert length(Accounts.list_workspaces_for_org(org.id)) == 1
      assert {"/with-ws", flash} = assert_redirect(view)
      assert flash["info"] =~ "created with a default workspace"
    end

    test "save with the default workspace box declined creates no workspace", %{} do
      user = user_fixture()
      {:ok, view, _html} = live(cloud_conn(user), ~p"/new/org")

      # A checkbox cannot submit "false" — an unchecked box is simply absent
      # from the payload — so the declined path is exercised at the event
      # level with no `create_default_workspace` param at all.
      render_submit(view, "save", %{"org" => %{"name" => "No WS", "slug" => "no-ws"}})

      org = Repo.get_by!(Org, slug: "no-ws")
      assert Accounts.list_workspaces_for_org(org.id) == []
      assert {"/no-ws", flash} = assert_redirect(view)
      assert flash["info"] =~ "Organization \"No WS\" created."
    end

    test "an invalid slug shows a validation error and creates nothing", %{} do
      user = user_fixture()
      {:ok, view, _html} = live(cloud_conn(user), ~p"/new/org")

      html =
        view
        |> form("#new-org-form", org: %{name: "Bad", slug: "Bad Slug!"})
        |> render_submit()

      refute Repo.get_by(Org, slug: "bad slug!")
      assert html =~ ~s(id="new-org-form")
      assert html =~ "has invalid format"
    end
  end
end
