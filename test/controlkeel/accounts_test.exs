defmodule ControlKeel.AccountsTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.{Membership, Org}
  alias ControlKeel.Repo

  describe "create_user/1" do
    test "creates a user with normalized email" do
      assert {:ok, user} =
               Accounts.create_user(%{email: "  Alice@Example.COM  ", name: "Alice"})

      assert user.email == "alice@example.com"
      assert user.status == "active"
      assert user.id
    end

    test "rejects bad email shapes" do
      assert {:error, changeset} = Accounts.create_user(%{email: "not-an-email"})
      assert "has invalid format" in errors_on(changeset).email
    end

    test "enforces unique email" do
      {:ok, _} = Accounts.create_user(%{email: "dup@example.com"})
      assert {:error, changeset} = Accounts.create_user(%{email: "Dup@Example.com"})
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "create_org/1" do
    test "creates an org with normalized slug" do
      assert {:ok, org} = Accounts.create_org(%{name: "Acme Inc", slug: "  ACME-INC "})
      assert org.slug == "acme-inc"
      assert org.status == "active"
    end

    test "rejects bad slugs" do
      assert {:error, changeset} = Accounts.create_org(%{name: "X", slug: "_bad start"})
      assert "has invalid format" in errors_on(changeset).slug
    end

    test "enforces unique slug" do
      {:ok, _} = Accounts.create_org(%{name: "One", slug: "shared-slug"})
      assert {:error, changeset} = Accounts.create_org(%{name: "Two", slug: "shared-slug"})
      assert "has already been taken" in errors_on(changeset).slug
    end
  end

  describe "create_org_with_owner/2" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "owner@example.com", name: "Owner"})
      {:ok, user: user}
    end

    test "creates an org and an active owner membership atomically", %{user: user} do
      assert {:ok, org} = Accounts.create_org_with_owner(user.id, %{name: "Acme", slug: "acme"})

      assert org.slug == "acme"
      assert org.status == "active"

      membership = Accounts.get_active_membership(user.id, org.id)
      assert membership != nil
      assert membership.role == "owner"
      assert membership.status == "active"
      assert membership.accepted_at != nil
      assert membership.invitation_token_hash == nil
    end

    test "rolls back both rows when the org insert fails", %{user: user} do
      {:ok, _} = Accounts.create_org(%{name: "Existing", slug: "taken"})

      assert {:error, changeset} =
               Accounts.create_org_with_owner(user.id, %{name: "Dup", slug: "taken"})

      assert "has already been taken" in errors_on(changeset).slug

      refute Repo.get_by(Org, slug: "taken") |> Map.get(:name) == "Dup"
      assert Repo.aggregate(Membership, :count) == 0
    end
  end

  describe "list_orgs_for_user/1" do
    test "returns only orgs where the user has an active membership, with role" do
      {:ok, user_a} = Accounts.create_user(%{email: "a@example.com"})
      {:ok, user_b} = Accounts.create_user(%{email: "b@example.com"})

      {:ok, org_a} = Accounts.create_org_with_owner(user_a.id, %{name: "Org A", slug: "org-a"})
      {:ok, _org_b} = Accounts.create_org_with_owner(user_b.id, %{name: "Org B", slug: "org-b"})

      # Unaffiliated org — should not appear for either user.
      {:ok, _} = Accounts.create_org(%{name: "Lonely", slug: "lonely"})

      [row_a] = Accounts.list_orgs_for_user(user_a.id)
      assert row_a.org.id == org_a.id
      assert row_a.role == "owner"
    end

    test "ignores pending memberships" do
      {:ok, owner} = Accounts.create_user(%{email: "owner@example.com"})
      {:ok, invitee} = Accounts.create_user(%{email: "invitee@example.com"})
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Own", slug: "own"})

      {:ok, _membership, _token} =
        Accounts.invite_member(invitee.id, org.id, role: "member", invited_by_user_id: owner.id)

      # Invitee has only a pending membership — they should not see the org.
      assert Accounts.list_orgs_for_user(invitee.id) == []

      [row] = Accounts.list_orgs_for_user(owner.id)
      assert row.org.id == org.id
      assert row.role == "owner"
    end

    test "preserves distinct roles when a user holds different roles across orgs" do
      {:ok, owner} = Accounts.create_user(%{email: "owner@example.com"})
      {:ok, other} = Accounts.create_user(%{email: "other@example.com"})

      {:ok, _owned} = Accounts.create_org_with_owner(owner.id, %{name: "Owned", slug: "owned"})

      {:ok, other_org} =
        Accounts.create_org_with_owner(other.id, %{name: "Other Org", slug: "other-org"})

      {:ok, _, token} =
        Accounts.invite_member(owner.id, other_org.id,
          role: "member",
          invited_by_user_id: other.id
        )

      {:ok, _} = Accounts.accept_invitation(token, owner.id)

      rows = Accounts.list_orgs_for_user(owner.id)
      role_by_slug = Map.new(rows, fn row -> {row.org.slug, row.role} end)

      assert role_by_slug["owned"] == "owner"
      assert role_by_slug["other-org"] == "member"
    end
  end

  describe "lookups" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "find@example.com", name: "Find"})
      {:ok, org} = Accounts.create_org(%{name: "Findable", slug: "findable"})
      {:ok, user: user, org: org}
    end

    test "get_user_by_email/1 is case insensitive", %{user: user} do
      assert Accounts.get_user_by_email("Find@Example.com").id == user.id
    end

    test "get_org_by_slug/1 is case insensitive", %{org: org} do
      assert Accounts.get_org_by_slug("FINDABLE").id == org.id
    end

    test "list filters by status" do
      {:ok, disabled} = Accounts.create_user(%{email: "x@example.com"})
      {:ok, _} = Accounts.disable_user(disabled.id)

      assert Enum.count(Accounts.list_users(status: "active")) == 1
      assert Enum.count(Accounts.list_users(status: "disabled")) == 1
    end
  end

  describe "invite_member/3 → accept_invitation/2" do
    setup do
      {:ok, owner} = Accounts.create_user(%{email: "owner@example.com"})
      {:ok, invitee} = Accounts.create_user(%{email: "invitee@example.com"})
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Team", slug: "team"})
      {:ok, owner: owner, invitee: invitee, org: org}
    end

    test "produces a one-time token; membership stores only its hash", %{
      invitee: invitee,
      org: org,
      owner: owner
    } do
      assert {:ok, membership, raw_token} =
               Accounts.invite_member(invitee.id, org.id,
                 role: "admin",
                 invited_by_user_id: owner.id
               )

      assert membership.status == "pending"
      assert membership.role == "admin"
      assert membership.invited_by_user_id == owner.id
      assert is_binary(raw_token)
      assert is_binary(membership.invitation_token_hash)
      refute membership.invitation_token_hash == raw_token
    end

    test "accepting flips status to active and clears the hash", %{invitee: invitee, org: org} do
      {:ok, _m, raw_token} = Accounts.invite_member(invitee.id, org.id)

      {:ok, accepted} = Accounts.accept_invitation(raw_token, invitee.id)

      assert accepted.status == "active"
      assert accepted.invitation_token_hash == nil
      assert %DateTime{} = accepted.accepted_at
    end

    test "rejects an invalid token", %{invitee: invitee} do
      assert {:error, :invalid_token} =
               Accounts.accept_invitation("nope-not-a-real-token", invitee.id)
    end

    test "rejects a token presented by the wrong user", %{
      invitee: invitee,
      owner: owner,
      org: org
    } do
      {:ok, _m, raw_token} = Accounts.invite_member(invitee.id, org.id)
      assert {:error, :invalid_token} = Accounts.accept_invitation(raw_token, owner.id)
    end

    test "rejects double-accept", %{invitee: invitee, org: org} do
      {:ok, _m, raw_token} = Accounts.invite_member(invitee.id, org.id)
      {:ok, _} = Accounts.accept_invitation(raw_token, invitee.id)

      assert {:error, :invalid_token} = Accounts.accept_invitation(raw_token, invitee.id)
    end

    test "prevents duplicate active membership for the same (user, org)", %{
      invitee: invitee,
      org: org
    } do
      {:ok, _m, _t} = Accounts.invite_member(invitee.id, org.id)
      assert {:error, :already_member} = Accounts.invite_member(invitee.id, org.id)
    end

    test "revives a revoked membership with a fresh token", %{
      invitee: invitee,
      org: org
    } do
      {:ok, owner} = Accounts.create_user(%{email: "reinvite-owner@example.com"})
      {:ok, _} = Accounts.create_org_with_owner(owner.id, %{name: "Owner Org", slug: "owner-org"})
      owner_org = Accounts.get_org_by_slug("owner-org")

      {:ok, _m, _t} = Accounts.invite_member(invitee.id, owner_org.id, role: "member")

      m =
        Accounts.list_memberships_for_org(owner_org.id) |> Enum.find(&(&1.user_id == invitee.id))

      {:ok, membership} = Accounts.revoke_membership(m.id, owner.id)
      assert membership.status == "revoked"
      assert membership.revoked_at != nil

      {:ok, revived, new_token} = Accounts.invite_member(invitee.id, owner_org.id, role: "admin")
      assert revived.status == "pending"
      assert revived.role == "admin"
      assert revived.accepted_at == nil
      assert revived.revoked_at == nil
      assert is_binary(new_token)

      {:ok, accepted} = Accounts.accept_invitation(new_token, invitee.id)
      assert accepted.status == "active"
    end

    test "rejects unknown role" do
      {:ok, invitee} = Accounts.create_user(%{email: "u@example.com"})
      {:ok, org} = Accounts.create_org(%{name: "X", slug: "x"})

      assert {:error, changeset} = Accounts.invite_member(invitee.id, org.id, role: "god")
      assert "is invalid" in errors_on(changeset).role
    end
  end

  describe "invite_member/3 authorization" do
    setup do
      {:ok, owner} = Accounts.create_user(%{email: "owner@example.com"})
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Auth Org", slug: "auth-org"})

      {:ok, admin} = Accounts.create_user(%{email: "admin@example.com"})

      {:ok, _, raw} =
        Accounts.invite_member(admin.id, org.id, role: "admin", invited_by_user_id: owner.id)

      {:ok, _} = Accounts.accept_invitation(raw, admin.id)

      {:ok, invitee} = Accounts.create_user(%{email: "invitee@example.com"})
      {:ok, owner: owner, admin: admin, invitee: invitee, org: org}
    end

    test "owner can invite at any role", %{owner: owner, invitee: invitee, org: org} do
      for role <- ["owner", "admin", "member", "viewer"] do
        # Fresh invitee per role to avoid already_member collisions.
        {:ok, u} = Accounts.create_user(%{email: "invitee-#{role}@example.com"})

        assert {:ok, m, _} =
                 Accounts.invite_member(u.id, org.id, role: role, invited_by_user_id: owner.id)

        assert m.role == role
      end
    end

    test "admin can invite member/viewer", %{admin: admin, invitee: invitee, org: org} do
      for role <- ["member", "viewer"] do
        {:ok, u} = Accounts.create_user(%{email: "invitee-#{role}-a@example.com"})

        assert {:ok, m, _} =
                 Accounts.invite_member(u.id, org.id, role: role, invited_by_user_id: admin.id)

        assert m.role == role
      end
    end

    test "admin cannot invite owner", %{admin: admin, invitee: invitee, org: org} do
      assert {:error, :unauthorized} =
               Accounts.invite_member(invitee.id, org.id,
                 role: "owner",
                 invited_by_user_id: admin.id
               )
    end

    test "admin cannot invite admin", %{admin: admin, invitee: invitee, org: org} do
      assert {:error, :unauthorized} =
               Accounts.invite_member(invitee.id, org.id,
                 role: "admin",
                 invited_by_user_id: admin.id
               )
    end

    test "non-member inviter is rejected", %{invitee: invitee, org: org} do
      {:ok, stranger} = Accounts.create_user(%{email: "stranger@example.com"})

      assert {:error, :unauthorized} =
               Accounts.invite_member(invitee.id, org.id,
                 role: "member",
                 invited_by_user_id: stranger.id
               )
    end

    test "nil inviter (operator path) is unrestricted", %{invitee: invitee, org: org} do
      assert {:ok, _, _} = Accounts.invite_member(invitee.id, org.id, role: "owner")
    end
  end

  describe "list_memberships_for_org/2 and list_memberships_for_user/2" do
    test "scope by org and by user" do
      {:ok, alice} = Accounts.create_user(%{email: "alice@example.com"})
      {:ok, bob} = Accounts.create_user(%{email: "bob@example.com"})
      {:ok, org_a} = Accounts.create_org(%{name: "A", slug: "a"})
      {:ok, org_b} = Accounts.create_org(%{name: "B", slug: "b"})

      {:ok, _, _} = Accounts.invite_member(alice.id, org_a.id)
      {:ok, _, _} = Accounts.invite_member(alice.id, org_b.id)
      {:ok, _, _} = Accounts.invite_member(bob.id, org_a.id)

      assert length(Accounts.list_memberships_for_org(org_a.id)) == 2
      assert length(Accounts.list_memberships_for_user(alice.id)) == 2
      assert length(Accounts.list_memberships_for_user(bob.id)) == 1
    end

    test "list_memberships_for_org/2 excludes revoked rows by default" do
      {:ok, owner} = Accounts.create_user(%{email: "filter-owner@example.com"})

      {:ok, _} =
        Accounts.create_org_with_owner(owner.id, %{name: "Filter Org", slug: "filter-org"})

      org = Accounts.get_org_by_slug("filter-org")

      {:ok, invitee} = Accounts.create_user(%{email: "filter-invitee@example.com"})
      {:ok, m, _token} = Accounts.invite_member(invitee.id, org.id, role: "member")

      # owner (active) + invitee (pending): neither revoked, both visible.
      assert length(Accounts.list_memberships_for_org(org.id)) == 2

      {:ok, _} = Accounts.revoke_membership(m.id, owner.id)

      rows = Accounts.list_memberships_for_org(org.id)
      assert length(rows) == 1
      assert Enum.all?(rows, &(&1.status != "revoked"))
    end

    test "list_memberships_for_org/2 include_revoked: true returns revoked rows" do
      {:ok, owner} = Accounts.create_user(%{email: "filter-owner2@example.com"})

      {:ok, _} =
        Accounts.create_org_with_owner(owner.id, %{name: "Filter Org 2", slug: "filter-org-2"})

      org = Accounts.get_org_by_slug("filter-org-2")

      {:ok, invitee} = Accounts.create_user(%{email: "filter-invitee2@example.com"})
      {:ok, m, _token} = Accounts.invite_member(invitee.id, org.id, role: "member")
      {:ok, _} = Accounts.revoke_membership(m.id, owner.id)

      rows = Accounts.list_memberships_for_org(org.id, include_revoked: true)
      assert length(rows) == 2
      assert Enum.any?(rows, &(&1.status == "revoked"))
    end

    test "list_memberships_for_org/2 status: \"revoked\" returns only revoked rows" do
      {:ok, owner} = Accounts.create_user(%{email: "filter-owner3@example.com"})

      {:ok, _} =
        Accounts.create_org_with_owner(owner.id, %{name: "Filter Org 3", slug: "filter-org-3"})

      org = Accounts.get_org_by_slug("filter-org-3")

      {:ok, invitee} = Accounts.create_user(%{email: "filter-invitee3@example.com"})
      {:ok, m, _token} = Accounts.invite_member(invitee.id, org.id, role: "member")
      {:ok, _} = Accounts.revoke_membership(m.id, owner.id)

      rows = Accounts.list_memberships_for_org(org.id, status: "revoked")
      assert length(rows) == 1
      assert hd(rows).status == "revoked"
    end
  end

  describe "workspace ↔ org linkage" do
    setup do
      {:ok, alice} = Accounts.create_user(%{email: "alice@example.com"})
      {:ok, bob} = Accounts.create_user(%{email: "bob@example.com"})
      {:ok, org_a} = Accounts.create_org(%{name: "Org A", slug: "org-a"})
      {:ok, org_b} = Accounts.create_org(%{name: "Org B", slug: "org-b"})

      ws_a = ControlKeel.MissionFixtures.workspace_fixture(%{name: "WS A", slug: "ws-a"})
      ws_b = ControlKeel.MissionFixtures.workspace_fixture(%{name: "WS B", slug: "ws-b"})

      ws_unaffiliated =
        ControlKeel.MissionFixtures.workspace_fixture(%{name: "WS Solo", slug: "ws-solo"})

      {:ok,
       alice: alice,
       bob: bob,
       org_a: org_a,
       org_b: org_b,
       ws_a: ws_a,
       ws_b: ws_b,
       ws_unaffiliated: ws_unaffiliated}
    end

    test "assign_workspace_to_org/2 links and unlinks", %{ws_a: ws, org_a: org} do
      assert {:ok, linked} = Accounts.assign_workspace_to_org(ws.id, org.id)
      assert linked.org_id == org.id

      assert {:ok, unlinked} = Accounts.assign_workspace_to_org(ws.id, nil)
      assert unlinked.org_id == nil
    end

    test "assign_workspace_to_org/2 returns :not_found for unknown workspace" do
      assert {:error, :not_found} = Accounts.assign_workspace_to_org(999_999, 1)
    end

    test "list_workspaces_for_org/1 returns only that org's workspaces", %{
      ws_a: ws_a,
      ws_b: ws_b,
      org_a: org_a,
      org_b: org_b
    } do
      {:ok, _} = Accounts.assign_workspace_to_org(ws_a.id, org_a.id)
      {:ok, _} = Accounts.assign_workspace_to_org(ws_b.id, org_b.id)

      assert [%{id: id}] = Accounts.list_workspaces_for_org(org_a.id)
      assert id == ws_a.id
    end

    test "list_unaffiliated_workspaces/0 excludes linked workspaces", %{
      ws_a: ws_a,
      ws_unaffiliated: solo,
      org_a: org_a
    } do
      {:ok, _} = Accounts.assign_workspace_to_org(ws_a.id, org_a.id)

      ids = Enum.map(Accounts.list_unaffiliated_workspaces(), & &1.id)
      assert solo.id in ids
      refute ws_a.id in ids
    end

    test "list_workspaces_for_user/1 follows active memberships", %{
      alice: alice,
      ws_a: ws_a,
      ws_b: ws_b,
      org_a: org_a,
      org_b: org_b
    } do
      {:ok, _} = Accounts.assign_workspace_to_org(ws_a.id, org_a.id)
      {:ok, _} = Accounts.assign_workspace_to_org(ws_b.id, org_b.id)

      {:ok, m_a, raw_a} = Accounts.invite_member(alice.id, org_a.id)
      {:ok, _} = Accounts.accept_invitation(raw_a, alice.id)
      _ = m_a

      {:ok, _, _raw_b} = Accounts.invite_member(alice.id, org_b.id)

      ids = Enum.map(Accounts.list_workspaces_for_user(alice.id), & &1.id)

      assert ws_a.id in ids
      refute ws_b.id in ids
    end

    test "list_workspaces_for_user/1 ignores revoked memberships", %{
      alice: alice,
      ws_a: ws_a,
      org_a: org_a
    } do
      {:ok, owner} = Accounts.create_user(%{email: "owner@example.com"})

      {:ok, _} =
        %ControlKeel.Accounts.Membership{}
        |> ControlKeel.Accounts.Membership.changeset(%{
          user_id: owner.id,
          org_id: org_a.id,
          role: "owner",
          status: "active",
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> ControlKeel.Repo.insert()

      {:ok, _} = Accounts.assign_workspace_to_org(ws_a.id, org_a.id)
      {:ok, m, raw} = Accounts.invite_member(alice.id, org_a.id)
      {:ok, _} = Accounts.accept_invitation(raw, alice.id)
      {:ok, _} = Accounts.revoke_membership(m.id, owner.id)

      assert Accounts.list_workspaces_for_user(alice.id) == []
    end

    test "list_workspaces_for_user/1 excludes unaffiliated workspaces", %{
      alice: alice,
      ws_unaffiliated: solo,
      org_a: org_a
    } do
      {:ok, _, raw} = Accounts.invite_member(alice.id, org_a.id)
      {:ok, _} = Accounts.accept_invitation(raw, alice.id)

      ids = Enum.map(Accounts.list_workspaces_for_user(alice.id), & &1.id)
      refute solo.id in ids
    end
  end

  describe "revoke_membership/2" do
    setup do
      {:ok, owner} = Accounts.create_user(%{email: "owner@example.com"})

      {:ok, org} =
        Accounts.create_org_with_owner(owner.id, %{
          name: "O",
          slug: "o-#{System.unique_integer([:positive])}"
        })

      {:ok, member} = Accounts.create_user(%{email: "member@example.com"})
      {:ok, m, raw} = Accounts.invite_member(member.id, org.id, role: "member")
      {:ok, _} = Accounts.accept_invitation(raw, member.id)
      {:ok, owner: owner, org: org, member: member, membership: m}
    end

    test "owner can revoke a member", %{owner: owner, membership: m} do
      {:ok, revoked} = Accounts.revoke_membership(m.id, owner.id)
      assert revoked.status == "revoked"
      assert revoked.revoked_at != nil
    end

    test "member cannot self-revoke (not admin+)", %{member: member, membership: m} do
      assert {:error, :unauthorized} = Accounts.revoke_membership(m.id, member.id)
    end

    test "admin can revoke others but not self", %{owner: owner, org: org} do
      {:ok, admin} = Accounts.create_user(%{email: "admin@example.com"})
      {:ok, _, raw} = Accounts.invite_member(admin.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw, admin.id)
      admin_m = Accounts.list_memberships_for_org(org.id) |> Enum.find(&(&1.user_id == admin.id))

      assert {:error, :cannot_self_revoke} = Accounts.revoke_membership(admin_m.id, admin.id)
    end

    test "non-admin cannot revoke", %{membership: m} do
      {:ok, outsider} = Accounts.create_user(%{email: "out@example.com"})

      {:ok, org2} =
        Accounts.create_org_with_owner(outsider.id, %{
          name: "O2",
          slug: "o2-#{System.unique_integer([:positive])}"
        })

      assert {:error, :unauthorized} = Accounts.revoke_membership(m.id, outsider.id)
    end

    test "admin cannot revoke an owner", %{owner: owner, org: org} do
      {:ok, admin} = Accounts.create_user(%{email: "admin@example.com"})
      {:ok, _, raw} = Accounts.invite_member(admin.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw, admin.id)
      {:ok, owner2} = Accounts.create_user(%{email: "owner2@example.com"})
      {:ok, _, raw2} = Accounts.invite_member(owner2.id, org.id, role: "owner")
      {:ok, _} = Accounts.accept_invitation(raw2, owner2.id)

      owner2_m =
        Accounts.list_memberships_for_org(org.id) |> Enum.find(&(&1.user_id == owner2.id))

      assert {:error, :cannot_revoke_owner} = Accounts.revoke_membership(owner2_m.id, admin.id)
    end

    test "admin cannot revoke another admin", %{owner: owner, org: org} do
      {:ok, admin1} = Accounts.create_user(%{email: "admin1@example.com"})
      {:ok, _, raw1} = Accounts.invite_member(admin1.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw1, admin1.id)

      {:ok, admin2} = Accounts.create_user(%{email: "admin2@example.com"})
      {:ok, _, raw2} = Accounts.invite_member(admin2.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw2, admin2.id)

      admin2_m =
        Accounts.list_memberships_for_org(org.id) |> Enum.find(&(&1.user_id == admin2.id))

      assert {:error, :cannot_revoke_admin} = Accounts.revoke_membership(admin2_m.id, admin1.id)
    end

    test "owner can revoke another owner if not the last", %{owner: owner, org: org} do
      {:ok, owner2} = Accounts.create_user(%{email: "owner2@example.com"})
      {:ok, _, raw} = Accounts.invite_member(owner2.id, org.id, role: "owner")
      {:ok, _} = Accounts.accept_invitation(raw, owner2.id)

      owner2_m =
        Accounts.list_memberships_for_org(org.id) |> Enum.find(&(&1.user_id == owner2.id))

      {:ok, revoked} = Accounts.revoke_membership(owner2_m.id, owner.id)
      assert revoked.status == "revoked"
    end

    test "owner cannot self-revoke if last owner", %{owner: owner, org: org} do
      owner_m = Accounts.list_memberships_for_org(org.id) |> Enum.find(&(&1.user_id == owner.id))
      assert {:error, :last_owner_protected} = Accounts.revoke_membership(owner_m.id, owner.id)
    end

    test "returns :not_found for unknown id" do
      {:ok, owner} = Accounts.create_user(%{email: "o@example.com"})
      assert {:error, :not_found} = Accounts.revoke_membership(999_999, owner.id)
    end
  end

  describe "update_membership_role/3" do
    setup do
      {:ok, owner} = Accounts.create_user(%{email: "owner@example.com"})

      {:ok, org} =
        Accounts.create_org_with_owner(owner.id, %{
          name: "O",
          slug: "o-#{System.unique_integer([:positive])}"
        })

      {:ok, member} = Accounts.create_user(%{email: "member@example.com"})
      {:ok, m, raw} = Accounts.invite_member(member.id, org.id, role: "member")
      {:ok, _} = Accounts.accept_invitation(raw, member.id)
      {:ok, owner: owner, org: org, member: member, membership: m}
    end

    test "owner can promote member to admin", %{owner: owner, membership: m} do
      {:ok, promoted} = Accounts.update_membership_role(m.id, "admin", owner.id)
      assert promoted.role == "admin"
    end

    test "owner can demote admin to member", %{owner: owner, org: org} do
      {:ok, admin} = Accounts.create_user(%{email: "admin@example.com"})
      {:ok, _, raw} = Accounts.invite_member(admin.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw, admin.id)
      admin_m = Accounts.list_memberships_for_org(org.id) |> Enum.find(&(&1.user_id == admin.id))

      {:ok, demoted} = Accounts.update_membership_role(admin_m.id, "member", owner.id)
      assert demoted.role == "member"
    end

    test "admin cannot change roles", %{org: org, membership: m} do
      {:ok, admin} = Accounts.create_user(%{email: "admin@example.com"})
      {:ok, _, raw} = Accounts.invite_member(admin.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw, admin.id)

      assert {:error, :unauthorized} = Accounts.update_membership_role(m.id, "admin", admin.id)
    end

    test "admin can self-demit to member", %{org: org} do
      {:ok, admin} = Accounts.create_user(%{email: "admin@example.com"})
      {:ok, _, raw} = Accounts.invite_member(admin.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw, admin.id)
      admin_m = Accounts.list_memberships_for_org(org.id) |> Enum.find(&(&1.user_id == admin.id))

      {:ok, demoted} = Accounts.update_membership_role(admin_m.id, "member", admin.id)
      assert demoted.role == "member"
    end

    test "admin can self-demit to viewer", %{org: org} do
      {:ok, admin} = Accounts.create_user(%{email: "admin2@example.com"})
      {:ok, _, raw} = Accounts.invite_member(admin.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw, admin.id)
      admin_m = Accounts.list_memberships_for_org(org.id) |> Enum.find(&(&1.user_id == admin.id))

      {:ok, demoted} = Accounts.update_membership_role(admin_m.id, "viewer", admin.id)
      assert demoted.role == "viewer"
    end

    test "admin cannot self-promote to owner", %{org: org} do
      {:ok, admin} = Accounts.create_user(%{email: "admin3@example.com"})
      {:ok, _, raw} = Accounts.invite_member(admin.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw, admin.id)
      admin_m = Accounts.list_memberships_for_org(org.id) |> Enum.find(&(&1.user_id == admin.id))

      assert {:error, :unauthorized} =
               Accounts.update_membership_role(admin_m.id, "owner", admin.id)
    end

    test "admin cannot change another admin's role", %{org: org} do
      {:ok, admin_a} = Accounts.create_user(%{email: "admin-a@example.com"})
      {:ok, _, raw_a} = Accounts.invite_member(admin_a.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw_a, admin_a.id)

      {:ok, admin_b} = Accounts.create_user(%{email: "admin-b@example.com"})
      {:ok, _, raw_b} = Accounts.invite_member(admin_b.id, org.id, role: "admin")
      {:ok, _} = Accounts.accept_invitation(raw_b, admin_b.id)

      admin_b_m =
        Accounts.list_memberships_for_org(org.id) |> Enum.find(&(&1.user_id == admin_b.id))

      assert {:error, :unauthorized} =
               Accounts.update_membership_role(admin_b_m.id, "member", admin_a.id)
    end

    test "member cannot change roles", %{member: member, membership: m} do
      assert {:error, :unauthorized} = Accounts.update_membership_role(m.id, "viewer", member.id)
    end

    test "outsider cannot change roles", %{membership: m} do
      {:ok, outsider} = Accounts.create_user(%{email: "out@example.com"})

      {:ok, org2} =
        Accounts.create_org_with_owner(outsider.id, %{
          name: "O2",
          slug: "o2-#{System.unique_integer([:positive])}"
        })

      assert {:error, :unauthorized} =
               Accounts.update_membership_role(m.id, "viewer", outsider.id)
    end

    test "returns :not_found for unknown id", %{owner: owner} do
      assert {:error, :not_found} = Accounts.update_membership_role(999_999, "member", owner.id)
    end
  end

  describe "session_accessible?/2 (issue #141, R2)" do
    import ControlKeel.MissionFixtures, only: [workspace_fixture: 1, session_fixture: 1]

    setup do
      {:ok, org_a} =
        Accounts.create_org(%{name: "Org A", slug: "org-a-#{System.unique_integer([:positive])}"})

      {:ok, org_b} =
        Accounts.create_org(%{name: "Org B", slug: "org-b-#{System.unique_integer([:positive])}"})

      {:ok, user} =
        Accounts.create_user(%{email: "r2-#{System.unique_integer([:positive])}@example.com"})

      %Membership{}
      |> Membership.changeset(%{
        user_id: user.id,
        org_id: org_a.id,
        role: "viewer",
        status: "active"
      })
      |> Repo.insert!()

      ws_a = workspace_fixture(%{org_id: org_a.id})
      ws_b = workspace_fixture(%{org_id: org_b.id})
      session_a = session_fixture(%{workspace: ws_a})
      session_b = session_fixture(%{workspace: ws_b})

      %{user: user, org_a: org_a, org_b: org_b, session_a: session_a, session_b: session_b}
    end

    test "local mode is a passthrough even with no user", %{session_a: session} do
      assert Accounts.session_accessible?(session, nil)
    end

    test "cloud mode denies a missing user", %{session_a: session} do
      with_cloud_mode(fn ->
        refute Accounts.session_accessible?(session, nil)
      end)
    end

    test "cloud mode allows an active member of the owning org", %{
      user: user,
      session_a: session
    } do
      with_cloud_mode(fn ->
        assert Accounts.session_accessible?(session, user)
      end)
    end

    test "cloud mode denies cross-org access", %{user: user, session_b: session} do
      with_cloud_mode(fn ->
        refute Accounts.session_accessible?(session, user)
      end)
    end

    test "cloud mode denies a session with no workspace", %{user: user} do
      with_cloud_mode(fn ->
        refute Accounts.session_accessible?(%{workspace_id: nil}, user)
      end)
    end

    test "cloud mode denies when the workspace row is missing", %{user: user} do
      with_cloud_mode(fn ->
        refute Accounts.session_accessible?(%{workspace_id: -1}, user)
      end)
    end

    test "cloud mode denies unaffiliated workspaces (no owning org)", %{user: user} do
      unbound = workspace_fixture(%{})
      session = session_fixture(%{workspace: unbound})

      with_cloud_mode(fn ->
        refute Accounts.session_accessible?(session, user)
      end)
    end

    defp with_cloud_mode(fun) do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      try do
        fun.()
      after
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end
    end
  end
end
