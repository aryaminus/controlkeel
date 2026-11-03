defmodule ControlKeelWeb.OrgSuspensionTest do
  @moduledoc """
  A suspended org must be a real kill switch on the browser tier, and API
  authorization must fail closed when no credential was established.

  Before this change, `Accounts.authorize_cloud_execution/2` (API) refused a
  non-active org, but the browser gates — `OrgAccess.resolve/3` for org URLs
  and `WorkspaceAccess.check_membership/3` for workspace pages — did not, so
  disabling an org left its entire browser surface reachable. A suspended org
  resolves like a missing one (`:forbidden` with `:not_found` copy) so its
  lifecycle state is not enumerable. Separately,
  `APIHelpers.authorize_workspace_for_conn/3` returned `:ok` for any conn
  without an `:api_auth` assign.
  """
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts
  alias ControlKeelWeb.OrgAccess
  alias ControlKeelWeb.WorkspaceAccess

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, previous) end)
    :ok
  end

  defp org_with_owner do
    suffix = System.unique_integer([:positive])
    {:ok, owner} = Accounts.create_user(%{email: "owner-#{suffix}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{name: "Org #{suffix}", slug: "org-#{suffix}"})

    workspace = workspace_fixture(%{org_id: org.id})
    %{owner: owner, org: org, workspace: workspace}
  end

  describe "org suspension kill switch" do
    test "WorkspaceAccess denies a viewer when the org is suspended" do
      %{owner: owner, org: org, workspace: workspace} = org_with_owner()
      assert WorkspaceAccess.check(workspace, owner) == :ok

      {:ok, _} = Accounts.update_org(org, %{status: "disabled"})

      assert WorkspaceAccess.check(workspace, owner) == {:error, :suspended}
    end

    test "OrgAccess denies a member when the org is suspended" do
      %{owner: owner, org: org} = org_with_owner()
      assert {:ok, ^org, _membership} = OrgAccess.resolve(org.slug, owner)

      {:ok, _} = Accounts.update_org(org, %{status: "disabled"})

      assert {:error, %{kind: :forbidden}} = OrgAccess.resolve(org.slug, owner)
    end

    test "a suspended org reads exactly like a missing one" do
      %{owner: owner, org: org} = org_with_owner()
      {:ok, _} = Accounts.update_org(org, %{status: "disabled"})

      {:error, suspended} = OrgAccess.resolve(org.slug, owner)
      {:error, missing} = OrgAccess.resolve("no-such-org-#{System.unique_integer()}", owner)

      assert suspended.message == missing.message
      assert suspended.title == missing.title
    end

    test "suspension does not affect local mode" do
      %{owner: owner, org: org, workspace: workspace} = org_with_owner()
      {:ok, _} = Accounts.update_org(org, %{status: "disabled"})

      Application.put_env(:controlkeel, :runtime_mode, :local)

      assert WorkspaceAccess.check(workspace, owner) == :ok
      assert {:ok, _org, nil} = OrgAccess.resolve(org.slug, owner)
    end
  end

  describe "API fail-closed default" do
    test "authorize_workspace_for_conn denies when api_auth is absent" do
      conn = build_conn()

      assert ControlKeelWeb.APIHelpers.authorize_workspace_for_conn(conn, 1, "read") ==
               {:error, :forbidden}
    end

    test "authorize_workspace_for_conn allows an explicit local caller" do
      conn = build_conn() |> Plug.Conn.assign(:api_auth, %{type: :local})

      assert ControlKeelWeb.APIHelpers.authorize_workspace_for_conn(conn, 1, "read") == :ok
    end
  end
end
