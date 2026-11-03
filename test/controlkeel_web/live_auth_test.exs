defmodule ControlKeelWeb.LiveAuthTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.BenchmarkFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Repo

  # Issue #141, R3: in cloud mode every authenticated surface except the
  # organization and session creation pages requires an active membership.
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

  defp memberless_conn do
    {:ok, user} =
      Accounts.create_user(%{email: "lonely-#{System.unique_integer([:positive])}@example.com"})

    build_conn() |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end

  # Workspace creation is admin-gated on the org overview; a viewer pushing
  # the event directly must be refused and nothing may be persisted.
  defp viewer_cannot_create_workspaces(view, slug) do
    html =
      render_click(view, "save_workspace", %{
        "workspace" => %{
          "name" => "Nope",
          "slug" => slug <> Integer.to_string(System.unique_integer([:positive]))
        }
      })

    if html =~ "have permission to create workspaces" do
      true
    else
      flunk("expected viewer save_workspace to be refused, got:\n\n" <> html)
    end
  end

  defp member_conn(role \\ "viewer") do
    {:ok, org} =
      Accounts.create_org(%{name: "Home", slug: "home-#{System.unique_integer([:positive])}"})

    {:ok, user} =
      Accounts.create_user(%{email: "member-#{System.unique_integer([:positive])}@example.com"})

    insert_membership(user, org, role)

    conn = build_conn() |> Plug.Test.init_test_session(%{current_user_id: user.id})
    {conn, user, org}
  end

  defp insert_membership(user, org, role) do
    %Accounts.Membership{}
    |> Accounts.Membership.changeset(%{
      user_id: user.id,
      org_id: org.id,
      role: role,
      status: "active"
    })
    |> Repo.insert!()
  end

  defp create_owner(org) do
    {:ok, owner} =
      Accounts.create_user(%{email: "owner-#{System.unique_integer([:positive])}@example.com"})

    insert_membership(owner, org, "owner")
    owner
  end

  # The global benchmark run page (/benchmarks/runs/:id) is the retained
  # require_cloud_auth surface without page-local membership, so it exercises
  # the same gates the old global /benchmarks index did.
  test "memberless users are redirected to /new/org on authenticated pages" do
    assert {:error, {:redirect, %{to: "/new/org"}}} =
             live(memberless_conn(), ~p"/benchmarks/runs/999999")
  end

  test "memberless users can open organization creation" do
    {:ok, _view, html} = live(memberless_conn(), ~p"/new/org")
    assert html =~ "Create organization"
  end

  test "users with a membership render authenticated pages" do
    {conn, _user, _org} = member_conn()
    run = benchmark_run_fixture()

    {:ok, _view, html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    refute html =~ "Join or create an organization"
  end

  test "membership changes for another org do not elevate the page's resolved membership" do
    {:ok, org_a} =
      Accounts.create_org(%{name: "Org A", slug: "org-a-#{System.unique_integer([:positive])}"})

    {:ok, org_b} =
      Accounts.create_org(%{name: "Org B", slug: "org-b-#{System.unique_integer([:positive])}"})

    {:ok, user} =
      Accounts.create_user(%{email: "multi-#{System.unique_integer([:positive])}@example.com"})

    %Accounts.Membership{}
    |> Accounts.Membership.changeset(%{
      user_id: user.id,
      org_id: org_a.id,
      role: "viewer",
      status: "active"
    })
    |> Repo.insert!()

    %Accounts.Membership{}
    |> Accounts.Membership.changeset(%{
      user_id: user.id,
      org_id: org_b.id,
      role: "admin",
      status: "active"
    })
    |> Repo.insert!()

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{current_user_id: user.id})

    # The org overview is the canonical require_cloud_auth page since the
    # /cloud/* surfaces were removed. user is a viewer in org A and an admin
    # in org B; the page must resolve its membership from org A only. The
    # New Workspace button renders for everyone, so the role check is
    # asserted on the server-refused action, not on markup.
    {:ok, view, _html} = live(conn, ~p"/#{org_a.slug}")

    assert viewer_cannot_create_workspaces(view, "nope")

    Phoenix.PubSub.broadcast(
      ControlKeel.PubSub,
      Accounts.membership_topic(user.id),
      {:membership_changed, %{user_id: user.id, org_id: org_b.id}}
    )

    # The org B (admin) change must not elevate the org A page's role.
    assert viewer_cannot_create_workspaces(view, "still-no")

    refute ControlKeel.Repo.get_by(ControlKeel.Mission.Workspace, name: "Nope")
    refute ControlKeel.Repo.get_by(ControlKeel.Mission.Workspace, name: "Still No")
  end

  test "revoking the page's membership redirects to /new/org" do
    {conn, user, org} = member_conn()
    membership = Accounts.get_active_membership(user.id, org.id)
    owner = create_owner(org)

    {:ok, view, _html} = live(conn, ~p"/#{org.slug}")

    assert {:ok, %Accounts.Membership{status: "revoked"}} =
             Accounts.revoke_membership(membership.id, owner.id)

    assert %{"info" => "Your access to this organization changed."} =
             assert_redirect(view, "/new/org")
  end

  test "revoking a membership in another org leaves the page in place" do
    {conn, user, org} = member_conn()

    {:ok, other} =
      Accounts.create_org(%{
        name: "Other",
        slug: "other-#{System.unique_integer([:positive])}"
      })

    other_membership = insert_membership(user, other, "viewer")
    owner = create_owner(other)

    {:ok, view, _html} = live(conn, ~p"/#{org.slug}")

    assert {:ok, %Accounts.Membership{status: "revoked"}} =
             Accounts.revoke_membership(other_membership.id, owner.id)

    assert has_element?(view, "#org-delivery-funnel")
    refute_redirected(view)
  end

  test "revoking the last membership returns to /new/org, not the login screen" do
    {conn, user, org} = member_conn()
    membership = Accounts.get_active_membership(user.id, org.id)
    owner = create_owner(org)
    run = benchmark_run_fixture()

    {:ok, view, _html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    assert {:ok, %Accounts.Membership{status: "revoked"}} =
             Accounts.revoke_membership(membership.id, owner.id)

    assert %{"info" => "You no longer have access to any organization."} =
             assert_redirect(view, "/new/org")
  end

  test "unauthenticated users are still sent to login, not /new/org" do
    assert {:error, {:redirect, %{to: "/auth/login"}}} =
             live(build_conn(), ~p"/benchmarks/runs/999999")
  end
end
