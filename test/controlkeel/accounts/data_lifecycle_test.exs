defmodule ControlKeel.Accounts.DataLifecycleTest do
  @modagedoc """
  User/org erasure (issue #266).

  The contract under test: identity is purged, the audit *record* survives with
  the identity anonymized, and tenant-owned governance data is not destroyed by
  one person's account being erased.
  """
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.DataLifecycle
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Accounts.ReviewAuditEvent
  alias ControlKeel.Mission.FindingAuditEvent

  defp org_with_owner(slug) do
    n = System.unique_integer([:positive])
    {:ok, owner} = Accounts.create_user(%{email: "owner-#{n}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{name: "Org #{slug}", slug: slug})

    %{org: org, owner: owner}
  end

  defp member_of(org, owner, role) do
    n = System.unique_integer([:positive])
    {:ok, m} = Accounts.create_user(%{email: "member-#{n}@example.com"})

    {:ok, _mem, token} =
      Accounts.invite_member(m.id, org.id, role: role, invited_by_user_id: owner.id)

    {:ok, _} = Accounts.accept_invitation(token, m.id)
    m
  end

  describe "export_user_data/1 (Art.15)" do
    test "returns the user's own data without other members' data" do
      %{org: org, owner: owner} = org_with_owner("export-org")
      _other = member_of(org, owner, "member")

      assert {:ok, export} = DataLifecycle.export_user_data(owner.id)
      assert export.user.email == owner.email
      assert [%{org_id: org_id}] = export.memberships
      assert org_id == org.id
    end

    test "unknown user is not found" do
      assert {:error, :not_found} = DataLifecycle.export_user_data(999_999)
    end
  end

  describe "delete_user/1 (Art.17)" do
    test "purges the account and its memberships" do
      %{org: org, owner: owner} = org_with_owner("del-owner-org")
      member = member_of(org, owner, "member")

      assert {:ok, result} = DataLifecycle.delete_user(member.id)
      assert result.user_deleted
      assert result.memberships_deleted == 1

      assert Repo.get(Accounts.User, member.id) == nil
      assert Repo.get_by(Membership, user_id: member.id) == nil
    end

    test "refuses to delete the sole owner of an org" do
      %{owner: owner} = org_with_owner("sole-owner-org")

      # The org creator is the only owner; erasing them would orphan the org.
      assert {:error, :sole_owner} = DataLifecycle.delete_user(owner.id)
      assert Repo.get(Accounts.User, owner.id)
    end

    test "allows deleting an owner once another owner exists" do
      %{org: org, owner: owner} = org_with_owner("two-owner-org")
      second = member_of(org, owner, "owner")

      assert {:ok, _} = DataLifecycle.delete_user(second.id)
      assert Repo.get(Accounts.User, second.id) == nil
      # The org and the original owner survive.
      assert Repo.get(Accounts.Org, org.id)
      assert Repo.get(Accounts.User, owner.id)
    end

    test "anonymizes identity in audit rows but keeps the record" do
      %{org: org, owner: owner} = org_with_owner("audit-org")
      member = member_of(org, owner, "member")

      # An audit event attributed to the member.
      review = ControlKeel.MissionFixtures.review_fixture()

      event =
        Repo.insert!(%ReviewAuditEvent{
          review_id: review.id,
          event_type: "finding_approved",
          required_role: "admin",
          actor_role: "member",
          actor_source: "web",
          actor_identifier: member.email,
          actor_user_id: member.id,
          note: "ship it",
          recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:ok, _} = DataLifecycle.delete_user(member.id)

      # The row survives (compliance record intact)...
      kept = Repo.get(ReviewAuditEvent, event.id)
      assert kept
      # ...but the identity is gone.
      assert kept.actor_user_id == nil
      refute kept.actor_identifier == member.email
      assert kept.actor_identifier =~ "erased-user-"
    end

    test "does not destroy tenant-owned governance data on user delete" do
      %{org: org, owner: owner} = org_with_owner("retain-org")
      member = member_of(org, owner, "member")

      workspace = ControlKeel.MissionFixtures.workspace_fixture(%{org_id: org.id})
      session = ControlKeel.MissionFixtures.session_fixture(%{workspace: workspace})

      assert {:ok, _} = DataLifecycle.delete_user(member.id)

      # Org, workspace and session all survive - they belong to the tenant.
      assert Repo.get(Accounts.Org, org.id)
      assert Repo.get(ControlKeel.Mission.Workspace, workspace.id)
      assert Repo.get(ControlKeel.Mission.Session, session.id)
      _ = owner
    end
  end

  describe "delete_org/1" do
    test "purges the org and its workspaces" do
      %{org: org} = org_with_owner("del-org")
      workspace = ControlKeel.MissionFixtures.workspace_fixture(%{org_id: org.id})

      assert {:ok, result} = DataLifecycle.delete_org(org.id)
      assert result.org_deleted
      assert result.workspaces == 1

      assert Repo.get(Accounts.Org, org.id) == nil
      assert Repo.get(ControlKeel.Mission.Workspace, workspace.id) == nil
    end

    test "purges sessions and findings under the org" do
      %{org: org} = org_with_owner("cascade-org")
      workspace = ControlKeel.MissionFixtures.workspace_fixture(%{org_id: org.id})
      session = ControlKeel.MissionFixtures.session_fixture(%{workspace: workspace})

      assert {:ok, _} = DataLifecycle.delete_org(org.id)

      assert Repo.get(ControlKeel.Mission.Session, session.id) == nil
    end

    test "unknown org is not found" do
      assert {:error, :not_found} = DataLifecycle.delete_org(999_999)
    end
  end

  describe "finding audit anonymization" do
    test "anonymizes actor identity in finding audit events" do
      %{org: org, owner: owner} = org_with_owner("finding-audit-org")
      member = member_of(org, owner, "member")

      workspace = ControlKeel.MissionFixtures.workspace_fixture(%{org_id: org.id})
      session = ControlKeel.MissionFixtures.session_fixture(%{workspace: workspace})

      finding = ControlKeel.MissionFixtures.finding_fixture(%{session: session})

      event =
        Repo.insert!(%FindingAuditEvent{
          finding_id: finding.id,
          event_type: "escalated",
          previous_status: "open",
          new_status: "escalated",
          actor_source: "web",
          actor_identifier: member.email,
          actor_user_id: member.id,
          recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:ok, _} = DataLifecycle.delete_user(member.id)

      kept = Repo.get(FindingAuditEvent, event.id)
      assert kept
      assert kept.actor_user_id == nil
      assert kept.actor_identifier =~ "erased-user-"
    end
  end
end
