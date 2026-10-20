defmodule ControlKeelWeb.MembershipEvictionTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Repo

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

  defp create_membership!(user, org, role) do
    %Accounts.Membership{}
    |> Accounts.Membership.changeset(%{
      user_id: user.id,
      org_id: org.id,
      role: role,
      status: "active"
    })
    |> Repo.insert!()
  end

  defp create_user!(prefix) do
    {:ok, user} =
      Accounts.create_user(%{
        email: "#{prefix}-#{System.unique_integer([:positive])}@example.com"
      })

    user
  end

  defp create_org!(prefix) do
    suffix = System.unique_integer([:positive])
    {:ok, org} = Accounts.create_org(%{name: "#{prefix} #{suffix}", slug: "#{prefix}-#{suffix}"})
    org
  end

  defp org_with_workspace!(role \\ "admin") do
    org = create_org!("evict")
    user = create_user!("evict")
    membership = create_membership!(user, org, role)

    {:ok, workspace} =
      Mission.create_workspace(%{
        name: "Workspace #{System.unique_integer([:positive])}",
        slug: "ws-#{System.unique_integer([:positive])}",
        agent: "claude",
        industry: "web",
        compliance_profile: "general",
        status: "active",
        org_id: org.id
      })

    {org, user, membership, workspace}
  end

  defp conn_for(user) do
    build_conn() |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end

  defp workspace_path(org, workspace) do
    ~p"/#{org.slug}/workspaces/#{workspace.slug}"
  end

  describe "WorkspaceDetailLive" do
    test "revoking the page's membership redirects while other memberships remain" do
      {org, user, membership, workspace} = org_with_workspace!()

      # The user keeps an active membership elsewhere; the redirect must not
      # become a sign-out.
      other_org = create_org!("elsewhere")
      create_membership!(user, other_org, "viewer")

      owner = create_user!("owner")
      create_membership!(owner, org, "owner")

      {:ok, view, _html} = live(conn_for(user), workspace_path(org, workspace))

      assert {:ok, %Accounts.Membership{status: "revoked"}} =
               Accounts.revoke_membership(membership.id, owner.id)

      assert %{"info" => "Your access to this organization changed."} =
               assert_redirect(view, "/organizations")
    end

    test "role changes in another org leave the page in place" do
      {org, user, _membership, workspace} = org_with_workspace!()

      other_org = create_org!("other")
      other_membership = create_membership!(user, other_org, "viewer")
      other_owner = create_user!("other-owner")
      create_membership!(other_owner, other_org, "owner")

      {:ok, view, html} = live(conn_for(user), workspace_path(org, workspace))
      assert html =~ workspace.name

      assert {:ok, %Accounts.Membership{role: "admin"}} =
               Accounts.update_membership_role(other_membership.id, "admin", other_owner.id)

      refute_redirected(view)
      assert render(view) =~ workspace.name
    end

    test "local mode renders without a membership" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      {org, _user, _membership, workspace} = org_with_workspace!()

      {:ok, _view, html} = live(build_conn(), workspace_path(org, workspace))

      assert html =~ workspace.name
    end
  end

  describe "workspace admin tabs" do
    test "revoking the page's membership redirects from a workspace admin tab" do
      {org, user, membership, workspace} = org_with_workspace!()
      owner = create_user!("owner")
      create_membership!(owner, org, "owner")

      {:ok, view, _html} =
        live(conn_for(user), ~p"/#{org.slug}/workspaces/#{workspace.slug}/repos")

      assert {:ok, %Accounts.Membership{status: "revoked"}} =
               Accounts.revoke_membership(membership.id, owner.id)

      assert %{"info" => "Your access to this organization changed."} =
               assert_redirect(view, "/organizations")
    end
  end

  describe "role changes refresh the page in place" do
    test "demoting an admin hides management controls without a redirect" do
      {org, user, membership, _workspace} = org_with_workspace!("admin")
      owner = create_user!("owner")
      create_membership!(owner, org, "owner")

      {:ok, view, _html} = live(conn_for(user), ~p"/#{org.slug}?tab=members")
      assert has_element?(view, "#invite-member-button")

      assert {:ok, %Accounts.Membership{role: "viewer"}} =
               Accounts.update_membership_role(membership.id, "viewer", owner.id)

      refute_redirected(view)
      refute has_element?(view, "#invite-member-button")
    end

    test "demoting an owner disables owner-only settings" do
      {org, user, membership, _workspace} = org_with_workspace!("owner")
      other_owner = create_user!("other-owner")
      create_membership!(other_owner, org, "owner")

      {:ok, view, _html} = live(conn_for(user), ~p"/#{org.slug}/settings")
      refute render(view) =~ "Only owners can change status."

      assert {:ok, %Accounts.Membership{role: "admin"}} =
               Accounts.update_membership_role(membership.id, "admin", other_owner.id)

      refute_redirected(view)
      assert render(view) =~ "Only owners can change status."
    end
  end

  describe "SessionFindingsLive" do
    test "revoking the page's membership redirects from a read-only session page" do
      {org, user, membership, workspace} = org_with_workspace!("viewer")
      owner = create_user!("owner")
      create_membership!(owner, org, "owner")

      {:ok, session} =
        Mission.create_session(%{
          title: "Eviction findings",
          objective: "Check findings eviction",
          risk_tier: "low",
          status: "active",
          budget_cents: 1_000,
          spent_cents: 0,
          workspace_id: workspace.id
        })

      {:ok, view, _html} =
        live(
          conn_for(user),
          ~p"/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}/findings"
        )

      assert {:ok, %Accounts.Membership{status: "revoked"}} =
               Accounts.revoke_membership(membership.id, owner.id)

      assert %{"info" => "Your access to this organization changed."} =
               assert_redirect(view, "/organizations")
    end
  end
end
