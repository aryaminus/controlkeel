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

  test "local mode resolves without a user or membership", %{org: org} do
    Application.put_env(:controlkeel, :runtime_mode, :local)

    assert {:ok, %Accounts.Org{id: org_id}, nil} = OrgAccess.resolve(org.slug, nil, "admin")
    assert org_id == org.id
  end

  test "an unknown slug is :not_found", %{admin: admin} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    assert {:error, %{kind: :not_found} = error} = OrgAccess.resolve("no-such-org", admin)
    assert error.title == "Organization not found"
    assert error.org_slug == "no-such-org"
  end

  test "cloud mode denies a missing user", %{org: org} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    assert {:error, %{kind: :forbidden}} = OrgAccess.resolve(org.slug, nil)
  end

  test "members resolve at the viewer gate", %{org: org, viewer: viewer} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    assert {:ok, %Accounts.Org{id: org_id}, %Accounts.Membership{role: "viewer"}} =
             OrgAccess.resolve(org.slug, viewer)

    assert org_id == org.id
  end

  test "viewers and members are denied at the admin gate", %{
    org: org,
    viewer: viewer,
    member: member
  } do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    assert {:error, %{kind: :needs_admin}} = OrgAccess.resolve(org.slug, viewer, "admin")
    assert {:error, %{kind: :needs_admin}} = OrgAccess.resolve(org.slug, member, "admin")
  end

  test "admins resolve at the admin gate", %{org: org, admin: admin} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    assert {:ok, %Accounts.Org{id: org_id}, %Accounts.Membership{role: "admin"}} =
             OrgAccess.resolve(org.slug, admin, "admin")

    assert org_id == org.id
  end

  test "outsiders are forbidden at every gate", %{org: org, outsider: outsider} do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    assert {:error, %{kind: :forbidden}} = OrgAccess.resolve(org.slug, outsider)
    assert {:error, %{kind: :forbidden}} = OrgAccess.resolve(org.slug, outsider, "admin")
  end

  test "a forbidden org and a missing org share the same public copy", %{
    org: org,
    outsider: outsider
  } do
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    {:error, forbidden} = OrgAccess.resolve(org.slug, outsider)
    {:error, missing} = OrgAccess.resolve("no-such-org", outsider)

    assert forbidden.kind == :forbidden
    assert missing.kind == :not_found
    assert {forbidden.title, forbidden.message} == {missing.title, missing.message}
  end
end
