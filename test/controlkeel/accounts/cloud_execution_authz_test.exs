defmodule ControlKeel.Accounts.CloudExecutionAuthzTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.MissionFixtures
  alias ControlKeel.Repo

  describe "authorize_cloud_execution/2" do
    test "workspace changesets reject a missing org_id" do
      workspace = MissionFixtures.workspace_fixture()

      changeset = ControlKeel.Mission.Workspace.changeset(workspace, %{org_id: nil})

      assert "can't be blank" in errors_on(changeset).org_id
    end

    test "rejects org workspace without user_id" do
      org = insert_org()
      workspace = MissionFixtures.workspace_fixture(%{org_id: org.id})

      assert {:error, :unauthorized} =
               Accounts.authorize_cloud_execution(workspace.id)
    end

    test "rejects org workspace when user has no membership" do
      org = insert_org()
      workspace = MissionFixtures.workspace_fixture(%{org_id: org.id})
      user = insert_user("rando@example.com")

      assert {:error, :unauthorized} =
               Accounts.authorize_cloud_execution(workspace.id, user_id: user.id)
    end

    test "rejects viewer role when member is required" do
      org = insert_org()
      workspace = MissionFixtures.workspace_fixture(%{org_id: org.id})
      user = insert_user("viewer@example.com")
      insert_active_membership(user.id, org.id, "viewer")

      assert {:error, :unauthorized} =
               Accounts.authorize_cloud_execution(workspace.id, user_id: user.id)
    end

    test "authorizes member role" do
      org = insert_org()
      workspace = MissionFixtures.workspace_fixture(%{org_id: org.id})
      user = insert_user("member@example.com")
      insert_active_membership(user.id, org.id, "member")

      assert {:ok, :authorized} =
               Accounts.authorize_cloud_execution(workspace.id, user_id: user.id)
    end

    test "authorizes admin role" do
      org = insert_org()
      workspace = MissionFixtures.workspace_fixture(%{org_id: org.id})
      user = insert_user("admin@example.com")
      insert_active_membership(user.id, org.id, "admin")

      assert {:ok, :authorized} =
               Accounts.authorize_cloud_execution(workspace.id, user_id: user.id)
    end

    test "authorizes owner role" do
      org = insert_org()
      workspace = MissionFixtures.workspace_fixture(%{org_id: org.id})
      user = insert_user("owner@example.com")
      insert_active_membership(user.id, org.id, "owner")

      assert {:ok, :authorized} =
               Accounts.authorize_cloud_execution(workspace.id, user_id: user.id)
    end

    test "rejects cross-org user" do
      org_a = insert_org("org-a-" <> Integer.to_string(System.unique_integer([:positive])))
      org_b = insert_org("org-b-" <> Integer.to_string(System.unique_integer([:positive])))
      workspace = MissionFixtures.workspace_fixture(%{org_id: org_a.id})
      user = insert_user("crossorg@example.com")
      insert_active_membership(user.id, org_b.id, "owner")

      assert {:error, :unauthorized} =
               Accounts.authorize_cloud_execution(workspace.id, user_id: user.id)
    end

    test "rejects suspended org" do
      org = insert_org()
      {:ok, _} = org |> Accounts.Org.changeset(%{status: "disabled"}) |> Repo.update()
      workspace = MissionFixtures.workspace_fixture(%{org_id: org.id})
      user = insert_user("suspended@example.com")
      insert_active_membership(user.id, org.id, "owner")

      assert {:error, :org_suspended} =
               Accounts.authorize_cloud_execution(workspace.id, user_id: user.id)
    end

    test "rejects unknown workspace" do
      assert {:error, :not_found} =
               Accounts.authorize_cloud_execution(999_999, user_id: 1)
    end

    test "allows viewer when required_role is viewer" do
      org = insert_org()
      workspace = MissionFixtures.workspace_fixture(%{org_id: org.id})
      user = insert_user("viewer-ok@example.com")
      insert_active_membership(user.id, org.id, "viewer")

      assert {:ok, :authorized} =
               Accounts.authorize_cloud_execution(workspace.id,
                 user_id: user.id,
                 required_role: "viewer"
               )
    end
  end

  # ─────────────── helpers ───────────────

  defp insert_org(slug \\ nil) do
    s = slug || "org-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, org} =
      %Accounts.Org{}
      |> Accounts.Org.changeset(%{name: s, slug: s, status: "active"})
      |> Repo.insert()

    org
  end

  defp insert_user(email) do
    {:ok, user} = Accounts.create_user(%{email: email})
    user
  end

  defp insert_active_membership(user_id, org_id, role) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, membership} =
      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user_id,
        org_id: org_id,
        role: role,
        status: "active",
        accepted_at: now
      })
      |> Repo.insert()

    membership
  end
end
