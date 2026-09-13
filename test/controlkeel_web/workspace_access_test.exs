defmodule ControlKeelWeb.WorkspaceAccessTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Repo
  alias ControlKeelWeb.WorkspaceAccess

  setup do
    original = Application.get_env(:controlkeel, :runtime_mode)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original)
      end
    end)

    {:ok, org} =
      Accounts.create_org(%{name: "Acme", slug: "acme-#{System.unique_integer([:positive])}"})

    {:ok, other_org} =
      Accounts.create_org(%{name: "Other", slug: "other-#{System.unique_integer([:positive])}"})

    {:ok, admin} =
      Accounts.create_user(%{email: "admin-#{System.unique_integer([:positive])}@example.com"})

    {:ok, viewer} =
      Accounts.create_user(%{email: "viewer-#{System.unique_integer([:positive])}@example.com"})

    {:ok, outsider} =
      Accounts.create_user(%{email: "outsider-#{System.unique_integer([:positive])}@example.com"})

    for {user, role} <- [{admin, "admin"}, {viewer, "viewer"}] do
      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org.id,
        role: role,
        status: "active"
      })
      |> Repo.insert!()
    end

    workspace = workspace_fixture(%{org_id: org.id})
    unbound = workspace_fixture(%{})

    {:ok,
     admin: admin, viewer: viewer, outsider: outsider, workspace: workspace, unbound: unbound}
  end

  test "local mode is open, even without a user", %{workspace: ws} do
    Application.put_env(:controlkeel, :runtime_mode, :local)
    assert WorkspaceAccess.check(ws, nil, "admin") == :ok
  end

  test "cloud mode denies a missing user", %{workspace: ws} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert WorkspaceAccess.check(ws, nil, "viewer") == {:error, :forbidden}
  end

  test "cloud mode reports unbound workspaces distinctly", %{unbound: ws, admin: admin} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert WorkspaceAccess.check(ws, admin, "viewer") == {:error, :unbound}
  end

  test "cloud mode authorizes members at the viewer gate", %{workspace: ws, viewer: viewer} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert WorkspaceAccess.check(ws, viewer) == :ok
    assert WorkspaceAccess.check(ws, viewer, "viewer") == :ok
  end

  test "cloud mode rejects viewers at the admin gate", %{workspace: ws, viewer: viewer} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert WorkspaceAccess.check(ws, viewer, "admin") == {:error, :needs_admin}
  end

  test "cloud mode authorizes admins at the admin gate", %{workspace: ws, admin: admin} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert WorkspaceAccess.check(ws, admin, "admin") == :ok
  end

  test "cloud mode denies cross-org access", %{workspace: ws, outsider: outsider} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert WorkspaceAccess.check(ws, outsider, "viewer") == {:error, :forbidden}
    assert WorkspaceAccess.check(ws, outsider, "admin") == {:error, :forbidden}
  end
end
