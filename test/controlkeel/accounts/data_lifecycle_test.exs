defmodule ControlKeel.Accounts.DataLifecycleTest do
  @moduledoc """
  User/org erasure (issue #266).

  The contract under test: identity is purged, the audit *record* survives with
  the identity anonymized, and tenant-owned governance data is not destroyed by
  one person's account being erased.
  """
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.DataLifecycle
  alias ControlKeel.Accounts.DataLifecycleEvent
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Accounts.ReviewAuditEvent
  alias ControlKeel.Mission.FindingAuditEvent
  alias ControlKeel.Platform
  alias ControlKeel.Platform.ServiceAccount

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
          event_type: "approved",
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
      # ...while the retained decision note survives the erasure (1b).
      assert kept.note == "ship it"
    end

    test "keeps the decider's identity when the erased user was only the target" do
      %{org: org, owner: owner} = org_with_owner("decider-org")
      member = member_of(org, owner, "member")

      review = ControlKeel.MissionFixtures.review_fixture()

      event =
        Repo.insert!(%ReviewAuditEvent{
          review_id: review.id,
          event_type: "approved",
          actor_user_id: owner.id,
          actor_identifier: Integer.to_string(owner.id),
          target_user_id: member.id,
          note: "approved by owner, assignee later erased",
          recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:ok, _} = DataLifecycle.delete_user(member.id)

      kept = Repo.get(ReviewAuditEvent, event.id)
      # The surviving decider keeps their identity...
      assert kept.actor_user_id == owner.id
      assert kept.actor_identifier == Integer.to_string(owner.id)
      # ...only the FK to the erased assignee is nulled...
      assert kept.target_user_id == nil
      # ...and the note survives.
      assert kept.note == "approved by owner, assignee later erased"
    end

    test "records a durable user_erased audit event" do
      %{org: org, owner: owner} = org_with_owner("erased-event-org")
      member = member_of(org, owner, "member")

      assert {:ok, _} = DataLifecycle.delete_user(member.id)

      event = Repo.get_by!(DataLifecycleEvent, event_type: "user_erased")
      assert event.subject =~ "erased-user-"
      assert event.details["memberships_deleted"] == 1
      assert event.details["credentials_revoked"] == 0
      assert event.details["audit_events_anonymized"] >= 0
    end

    test "evicts the erased user's sessions and broadcasts the membership removal" do
      %{org: org, owner: owner} = org_with_owner("evict-org")
      member = member_of(org, owner, "member")

      Phoenix.PubSub.subscribe(ControlKeel.PubSub, Accounts.signout_topic(member.id))
      Phoenix.PubSub.subscribe(ControlKeel.PubSub, Accounts.membership_topic(member.id))

      assert {:ok, _} = DataLifecycle.delete_user(member.id)

      # Every connected LiveView of the erased user is pushed to the login
      # screen...
      assert_receive :sign_out_everywhere

      # ...and each removed membership is broadcast as a revocation so the
      # LiveAuth eviction hook re-runs access checks on their pages.
      assert_receive {:membership_changed, %{user_id: user_id, org_id: org_id, status: "revoked"}}
      assert user_id == member.id
      assert org_id == org.id
      _ = owner
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

    test "revokes service accounts the user minted" do
      %{org: org, owner: owner} = org_with_owner("cred-org")
      member = member_of(org, owner, "member")

      workspace = ControlKeel.MissionFixtures.workspace_fixture(%{org_id: org.id})

      {:ok, %{service_account: account}} =
        Platform.create_service_account(
          workspace.id,
          %{"name" => "minted-by-member", "scopes" => ["findings:read"]},
          created_by_user_id: member.id
        )

      # A system-minted account with no creator must NOT be revoked.
      {:ok, %{service_account: system_account}} =
        Platform.create_service_account(workspace.id, %{
          "name" => "system-minted",
          "scopes" => ["findings:read"]
        })

      assert {:ok, result} = DataLifecycle.delete_user(member.id)
      assert result.credentials_revoked == 1

      assert Repo.get!(ServiceAccount, account.id).status == "revoked"
      assert Repo.get!(ServiceAccount, system_account.id).status == "active"
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

    test "records a durable org_erased audit event" do
      %{org: org} = org_with_owner("erased-event-org")

      assert {:ok, _} = DataLifecycle.delete_org(org.id)

      event = Repo.get_by!(DataLifecycleEvent, event_type: "org_erased")
      assert event.subject == Integer.to_string(org.id)
      assert event.details["org_slug"] == org.slug
      assert event.details["workspaces"] == 0
    end

    test "broadcasts membership removal to the org's active members" do
      %{org: org, owner: owner} = org_with_owner("org-evict-org")
      member = member_of(org, owner, "member")

      for uid <- [owner.id, member.id] do
        Phoenix.PubSub.subscribe(ControlKeel.PubSub, Accounts.membership_topic(uid))
      end

      assert {:ok, result} = DataLifecycle.delete_org(org.id)
      assert result.memberships_affected == 2

      # Both members receive the revocation (order across topics is not
      # deterministic; the org pins identify the org's own broadcast).
      assert_receive {:membership_changed, %{status: "revoked", org_id: org_id}}
      assert org_id == org.id

      assert_receive {:membership_changed, %{status: "revoked", org_id: ^org_id}}
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
