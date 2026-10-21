defmodule ControlKeelWeb.MembershipEvictionTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Repo

  # Every workspace-scoped observability route; all are viewer-readable and
  # mounted through ControlKeelWeb.WorkspaceScope.
  @observability_surfaces ~w(
    observability
    observability/loop
    observability/compare
    observability/costs
    observability/evals
    observability/imports
    observability/memory-quality
    observability/recommendations
    observability/trends
    observability/promotions
    observability/benchmark
  )

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

    {org, user, membership, create_workspace!(org)}
  end

  defp create_workspace!(org) do
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

    workspace
  end

  defp create_session!(workspace, title) do
    {:ok, session} =
      Mission.create_session(%{
        title: title,
        objective: "Check observability scope",
        risk_tier: "low",
        status: "active",
        budget_cents: 1_000,
        spent_cents: 0,
        workspace_id: workspace.id
      })

    session
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

  describe "observability pages" do
    test "every observability surface evicts the page membership on revocation" do
      for surface <- @observability_surfaces do
        {org, user, membership, workspace} = org_with_workspace!("viewer")
        owner = create_user!("owner")
        create_membership!(owner, org, "owner")

        {:ok, view, html} =
          live(
            conn_for(user),
            "/#{org.slug}/workspaces/#{workspace.slug}/#{surface}"
          )

        assert html =~ workspace.name, "#{surface} did not render the workspace chrome"

        assert {:ok, %Accounts.Membership{status: "revoked"}} =
                 Accounts.revoke_membership(membership.id, owner.id)

        assert %{"info" => "Your access to this organization changed."} =
                 assert_redirect(view, "/organizations"),
               "#{surface} did not evict the revoked membership"
      end
    end

    test "revoking the page's membership redirects while other memberships remain" do
      {org, user, membership, workspace} = org_with_workspace!("viewer")

      # The user keeps an active membership elsewhere; the redirect must not
      # become a sign-out.
      other_org = create_org!("elsewhere")
      create_membership!(user, other_org, "viewer")

      owner = create_user!("owner")
      create_membership!(owner, org, "owner")

      {:ok, view, _html} =
        live(conn_for(user), ~p"/#{org.slug}/workspaces/#{workspace.slug}/observability")

      assert {:ok, %Accounts.Membership{status: "revoked"}} =
               Accounts.revoke_membership(membership.id, owner.id)

      assert %{"info" => "Your access to this organization changed."} =
               assert_redirect(view, "/organizations")
    end

    test "demoting an admin hides observability mutation controls without a redirect" do
      {org, user, membership, workspace} = org_with_workspace!("admin")
      owner = create_user!("owner")
      create_membership!(owner, org, "owner")

      {:ok, view, _html} =
        live(
          conn_for(user),
          ~p"/#{org.slug}/workspaces/#{workspace.slug}/observability/benchmark"
        )

      assert has_element?(view, "#observability-benchmark-drafts-generate")

      assert {:ok, %Accounts.Membership{role: "viewer"}} =
               Accounts.update_membership_role(membership.id, "viewer", owner.id)

      refute_redirected(view)
      refute has_element?(view, "#observability-benchmark-drafts-generate")

      # The event stays denied after the demotion, not just hidden.
      assert render_click(view, "generate-drafts") =~ "Admin or owner role required."
    end

    test "role changes in another org leave the observability page in place" do
      {org, user, _membership, workspace} = org_with_workspace!("viewer")

      other_org = create_org!("other")
      other_membership = create_membership!(user, other_org, "viewer")
      other_owner = create_user!("other-owner")
      create_membership!(other_owner, other_org, "owner")

      {:ok, view, html} =
        live(conn_for(user), ~p"/#{org.slug}/workspaces/#{workspace.slug}/observability")

      assert html =~ workspace.name

      assert {:ok, %Accounts.Membership{role: "admin"}} =
               Accounts.update_membership_role(other_membership.id, "admin", other_owner.id)

      refute_redirected(view)
      assert render(view) =~ workspace.name
    end

    test "patching to another workspace in the same org reloads the page" do
      {org, user, _membership, workspace} = org_with_workspace!("viewer")
      other_workspace = create_workspace!(org)
      create_session!(workspace, "First workspace run")
      create_session!(other_workspace, "Second workspace run A")
      create_session!(other_workspace, "Second workspace run B")

      {:ok, view, html} =
        live(conn_for(user), ~p"/#{org.slug}/workspaces/#{workspace.slug}/observability")

      assert html =~ workspace.name
      assert element(view, "#observability-overview-runs") |> render() =~ "1 recent"

      assert render_patch(view, ~p"/#{org.slug}/workspaces/#{other_workspace.slug}/observability") =~
               other_workspace.name

      refute_redirected(view)
      assert render(view) =~ other_workspace.name
      assert element(view, "#observability-overview-runs") |> render() =~ "2 recent"
    end

    test "patching to an inaccessible organization's workspace redirects" do
      {org, user, _membership, workspace} = org_with_workspace!("viewer")

      other_org = create_org!("no-membership")
      other_workspace = create_workspace!(other_org)

      {:ok, view, html} =
        live(conn_for(user), ~p"/#{org.slug}/workspaces/#{workspace.slug}/observability")

      assert html =~ workspace.name

      render_patch(view, ~p"/#{other_org.slug}/workspaces/#{other_workspace.slug}/observability")

      assert %{"error" => "Workspace belongs to a different organization."} =
               assert_redirect(view, "/organizations")
    end

    test "local mode renders without a membership" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      {org, _user, _membership, workspace} = org_with_workspace!()

      {:ok, _view, html} =
        live(build_conn(), ~p"/#{org.slug}/workspaces/#{workspace.slug}/observability")

      assert html =~ workspace.name
    end
  end

  describe "CloudTelemetryLive" do
    # The operator dashboard resolves its org from the visitor's default
    # membership (no org in the URL), so these users carry a single membership.
    test "demoting the operator membership leaves the dashboard" do
      org = create_org!("operator")
      user = create_user!("operator")
      membership = create_membership!(user, org, "admin")
      owner = create_user!("operator-owner")
      create_membership!(owner, org, "owner")

      {:ok, view, html} = live(conn_for(user), "/cloud/telemetry")
      assert html =~ "cloud-telemetry-page"

      assert {:ok, %Accounts.Membership{role: "viewer"}} =
               Accounts.update_membership_role(membership.id, "viewer", owner.id)

      send(view.pid, :refresh)

      assert %{"error" => "Admin access required."} = assert_redirect(view, "/")
    end

    test "revoking the operator membership redirects to organizations" do
      org = create_org!("operator")
      user = create_user!("operator")
      membership = create_membership!(user, org, "admin")
      owner = create_user!("operator-owner")
      create_membership!(owner, org, "owner")

      {:ok, view, _html} = live(conn_for(user), "/cloud/telemetry")

      assert {:ok, %Accounts.Membership{status: "revoked"}} =
               Accounts.revoke_membership(membership.id, owner.id)

      assert %{"info" => "Your access to this organization changed."} =
               assert_redirect(view, "/organizations")
    end
  end
end
