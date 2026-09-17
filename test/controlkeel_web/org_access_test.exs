defmodule ControlKeelWeb.OrgAccessTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Repo
  alias ControlKeelWeb.OrgAccess

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

    {:ok, admin} =
      Accounts.create_user(%{email: "admin-#{System.unique_integer([:positive])}@example.com"})

    {:ok, member} =
      Accounts.create_user(%{email: "member-#{System.unique_integer([:positive])}@example.com"})

    {:ok, viewer} =
      Accounts.create_user(%{email: "viewer-#{System.unique_integer([:positive])}@example.com"})

    {:ok, outsider} =
      Accounts.create_user(%{email: "outsider-#{System.unique_integer([:positive])}@example.com"})

    for {user, role} <- [{admin, "admin"}, {member, "member"}, {viewer, "viewer"}] do
      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org.id,
        role: role,
        status: "active"
      })
      |> Repo.insert!()
    end

    {:ok, admin: admin, member: member, viewer: viewer, outsider: outsider, org: org}
  end

  test "local mode is open, even without a user", %{org: org} do
    Application.put_env(:controlkeel, :runtime_mode, :local)
    assert OrgAccess.check(org, nil, "admin") == {:ok, nil}
  end

  test "cloud mode denies a missing user", %{org: org} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert OrgAccess.check(org, nil, "viewer") == {:error, :forbidden}
  end

  test "cloud mode denies a missing org", %{admin: admin} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert OrgAccess.check(nil, admin, "viewer") == {:error, :forbidden}
  end

  test "cloud mode authorizes members at the viewer gate", %{org: org, viewer: viewer} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    assert {:ok, %Accounts.Membership{role: "viewer"}} = OrgAccess.check(org, viewer)
    assert {:ok, %Accounts.Membership{role: "viewer"}} = OrgAccess.check(org, viewer, "viewer")
  end

  test "cloud mode rejects viewers and members at the admin gate", %{
    org: org,
    viewer: viewer,
    member: member
  } do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert OrgAccess.check(org, viewer, "admin") == {:error, :needs_admin}
    assert OrgAccess.check(org, member, "admin") == {:error, :needs_admin}
  end

  test "cloud mode authorizes admins at the admin gate", %{org: org, admin: admin} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert {:ok, %Accounts.Membership{role: "admin"}} = OrgAccess.check(org, admin, "admin")
  end

  test "cloud mode denies outsiders at every gate", %{org: org, outsider: outsider} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert OrgAccess.check(org, outsider, "viewer") == {:error, :forbidden}
    assert OrgAccess.check(org, outsider, "admin") == {:error, :forbidden}
  end
end
