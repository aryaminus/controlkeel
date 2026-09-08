defmodule ControlKeelWeb.OrganizationSettingsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Repo

  # The settings page only enforces membership access in cloud mode; local
  # mode is unrestricted. These tests exercise the permission-gated UI, so
  # they run in cloud mode.
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

  defp create_user!(email) do
    {:ok, user} = Accounts.create_user(%{email: email})
    user
  end

  defp add_active_membership(user_id, org_id, role) do
    %Membership{}
    |> Membership.changeset(%{user_id: user_id, org_id: org_id, role: role, status: "active"})
    |> Repo.insert!()
  end

  defp conn_for(user),
    do: build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

  defp org_with_members do
    owner = create_user!("owner@example.com")
    {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Acme", slug: "acme"})

    admin = create_user!("admin@example.com")
    add_active_membership(admin.id, org.id, "admin")

    member = create_user!("member@example.com")
    add_active_membership(member.id, org.id, "member")

    %{org: org, owner: owner, admin: admin, member: member}
  end

  describe "access" do
    test "redirects for an unknown slug" do
      user = create_user!("nobody@example.com")

      assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
               live(conn_for(user), ~p"/organizations/nope/settings")

      assert msg =~ "Organization not found."
    end

    test "redirects signed-out users to login" do
      {:ok, _} = Accounts.create_org(%{name: "Acme", slug: "acme"})

      assert {:error, {:redirect, %{to: to}}} =
               live(build_conn(), ~p"/organizations/acme/settings")

      assert to == "/auth/login"
    end

    test "redirects non-members to /organizations" do
      %{org: org} = org_with_members()
      outsider = create_user!("outsider@example.com")

      assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
               live(conn_for(outsider), ~p"/organizations/#{org.slug}/settings")

      assert msg =~ "not a member"
    end
  end

  describe "admin viewer" do
    setup do
      %{org: org, admin: admin} = org_with_members()
      %{org: org, conn: conn_for(admin)}
    end

    test "renders the general panel", %{conn: conn, org: org} do
      {:ok, view, html} = live(conn, ~p"/organizations/#{org.slug}/settings")

      assert html =~ "Organization settings"
      assert has_element?(view, "#org-settings-form")
      assert html =~ org.slug

      assert html =~ ~s(href="/organizations/#{org.slug}")
      assert html =~ "Overview"
      refute html =~ "Policy Studio"
    end

    test "renames the organization", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/organizations/#{org.slug}/settings")

      html =
        view
        |> element("#org-settings-form")
        |> render_submit(%{"settings" => %{"name" => "Acme Renamed"}})

      assert html =~ "Settings saved."
      assert Accounts.get_org(org.id).name == "Acme Renamed"
    end

    test "status and budget inputs are locked for non-owners", %{conn: conn, org: org} do
      {:ok, view, html} = live(conn, ~p"/organizations/#{org.slug}/settings")

      status_input =
        view |> element("#org-settings-form select[name='settings[status]']") |> render()

      assert status_input =~ "disabled"
      assert html =~ "Only owners can change status."

      budget_input =
        view |> element("#org-settings-form input[name='settings[budget_cents]']") |> render()

      assert budget_input =~ "disabled"
      assert html =~ "Only owners can change budget."
    end

    test "org detail page shows the settings link in the sidebar", %{conn: conn, org: org} do
      {:ok, _view, html} = live(conn, ~p"/organizations/#{org.slug}")

      assert html =~ ~s(href="/organizations/#{org.slug}/settings")
    end
  end

  describe "member viewer" do
    test "name input is locked and saves are rejected server-side" do
      %{org: org, member: member} = org_with_members()

      {:ok, view, html} = live(conn_for(member), ~p"/organizations/#{org.slug}/settings")

      name_input = view |> element("#org-settings-form input[name='settings[name]']") |> render()
      assert name_input =~ "disabled"
      assert html =~ "Only admins and owners can rename."

      submit_html =
        view
        |> element("#org-settings-form")
        |> render_submit(%{"settings" => %{"name" => "Hacked"}})

      assert submit_html =~ "have permission to change organization settings"
      assert Accounts.get_org(org.id).name == org.name
    end
  end

  describe "owner viewer" do
    setup do
      %{org: org, owner: owner} = org_with_members()
      %{org: org, conn: conn_for(owner)}
    end

    test "updates status and budget", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/organizations/#{org.slug}/settings")

      html =
        view
        |> element("#org-settings-form")
        |> render_submit(%{
          "settings" => %{"name" => org.name, "status" => "disabled", "budget_cents" => "5000"}
        })

      assert html =~ "Settings saved."
      reloaded = Accounts.get_org(org.id)
      assert reloaded.status == "disabled"
      assert Accounts.org_budget_cents(reloaded) == 5000
    end

    test "invalid budget flashes an error", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/organizations/#{org.slug}/settings")

      view
      |> element("#org-settings-form")
      |> render_submit(%{"settings" => %{"name" => org.name, "budget_cents" => "-5"}})

      assert render(view) =~ "Budget must be a non-negative integer"
    end
  end
end
