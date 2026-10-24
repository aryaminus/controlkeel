defmodule ControlKeelWeb.MembershipEvictionTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

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

  @session_surfaces ~w(
    activity
    findings
    observability
    reviews
    tasks
    resume-packet
    connect
    release
    ship
    proofs
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
    test "revoking membership from a missing-workspace page redirects" do
      org = create_org!("missing-workspace")
      user = create_user!("missing-workspace")
      membership = create_membership!(user, org, "viewer")
      other_org = create_org!("still-member")
      create_membership!(user, other_org, "viewer")

      owner = create_user!("missing-workspace-owner")
      create_membership!(owner, org, "owner")

      {:ok, view, _html} =
        live(conn_for(user), ~p"/#{org.slug}/workspaces/does-not-exist")

      assert has_element?(view, "[data-scope-error]")
      assert has_element?(view, "#app-sidebar")

      assert {:ok, %Accounts.Membership{status: "revoked"}} =
               Accounts.revoke_membership(membership.id, owner.id)

      assert %{"info" => "Your access to this organization changed."} =
               assert_redirect(view, "/organizations")
    end

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

  describe "session-scoped pages" do
    test "task mutations reauthorize after cloud membership is revoked" do
      {org, user, membership, workspace} = org_with_workspace!("admin")
      session = create_session!(workspace, "Task mutation authorization")
      task = task_fixture(%{session: session, status: "in_progress"})

      {:ok, view, _html} =
        live(
          conn_for(user),
          "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}/tasks"
        )

      # Update without broadcasting to model an action arriving before the
      # connected LiveView processes its membership-change notification.
      membership
      |> Ecto.Changeset.change(status: "revoked")
      |> Repo.update!()

      render_click(view, "pause_task", %{"id" => task.id})

      assert Mission.get_task!(task.id).status == "in_progress"
      assert has_element?(view, "[data-scope-error]")
    end

    test "invalid session ids render in place with workspace navigation across session pages" do
      for surface <- ["root" | @session_surfaces] do
        {org, user, _membership, workspace} = org_with_workspace!("viewer")
        _session = create_session!(workspace, "Valid session")

        path =
          if surface == "root" do
            "/#{org.slug}/workspaces/#{workspace.slug}/sessions/invalid-session-id"
          else
            "/#{org.slug}/workspaces/#{workspace.slug}/sessions/invalid-session-id/#{surface}"
          end

        {:ok, view, _html} = live(conn_for(user), path)

        assert has_element?(view, "[data-scope-error]"), "#{surface} omitted the scope error"
        assert has_element?(view, "#app-sidebar"), "#{surface} lost organization navigation"

        assert has_element?(
                 view,
                 ~s(#app-sidebar a[href="/#{org.slug}/workspaces/#{workspace.slug}"])
               ),
               "#{surface} lost workspace navigation"

        assert has_element?(view, "h1", "Can't find the page")
        refute_redirected(view)
      end
    end

    test "every session page evicts the page membership immediately on revocation" do
      for surface <- @session_surfaces do
        {org, user, membership, workspace} = org_with_workspace!("viewer")
        session = create_session!(workspace, "Session scope eviction")
        owner = create_user!("session-owner")
        create_membership!(owner, org, "owner")

        path = "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}/#{surface}"
        {:ok, view, _html} = live(conn_for(user), path)

        assert {:ok, %Accounts.Membership{status: "revoked"}} =
                 Accounts.revoke_membership(membership.id, owner.id)

        assert %{"info" => "Your access to this organization changed."} =
                 assert_redirect(view, "/organizations"),
               "#{surface} did not evict the revoked membership"
      end
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

    test "patching to an inaccessible organization's workspace renders an in-place scope error" do
      {org, user, _membership, workspace} = org_with_workspace!("viewer")

      other_org = create_org!("no-membership")
      other_workspace = create_workspace!(other_org)

      {:ok, view, html} =
        live(conn_for(user), ~p"/#{org.slug}/workspaces/#{workspace.slug}/observability")

      assert html =~ workspace.name

      path = ~p"/#{other_org.slug}/workspaces/#{other_workspace.slug}/observability"
      render_patch(view, path)

      assert has_element?(view, "[data-scope-error]")
      refute has_element?(view, "#observability-overview-page")
      refute_redirected(view)
    end

    test "patching to an inaccessible workspace blocks stale workspace mutations" do
      {org, user, _membership, workspace} = org_with_workspace!("admin")
      other_org = create_org!("no-workspace-access")
      other_workspace = create_workspace!(other_org)

      {:ok, view, _html} =
        live(conn_for(user), ~p"/#{org.slug}/workspaces/#{workspace.slug}/settings")

      render_patch(view, ~p"/#{other_org.slug}/workspaces/#{other_workspace.slug}/settings")

      assert has_element?(view, "[data-scope-error]")
      assert Accounts.get_workspace_tool_policy(workspace.id).mode == "inherit"

      render_submit(view, "submit", %{
        "policy" => %{"mode" => "denylist", "tools" => "mcp__controlkeel__ck_validate"}
      })

      assert Accounts.get_workspace_tool_policy(workspace.id).mode == "inherit"
      assert has_element?(view, "[data-scope-error]")
    end

    test "local mode renders without a membership" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      {org, _user, _membership, workspace} = org_with_workspace!()

      {:ok, _view, html} =
        live(build_conn(), ~p"/#{org.slug}/workspaces/#{workspace.slug}/observability")

      assert html =~ workspace.name
    end
  end
end
