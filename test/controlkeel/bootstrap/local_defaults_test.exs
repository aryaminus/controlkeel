defmodule ControlKeel.Bootstrap.LocalDefaultsTest do
  use ControlKeel.DataCase

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Bootstrap.LocalDefaults
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo

  describe "ensure/0 in local mode" do
    test "creates the default org and workspace linked together" do
      assert {:ok, {org, workspace}} = LocalDefaults.ensure()

      assert %Org{} = org
      assert org.slug == LocalDefaults.default_org_slug()
      assert %Workspace{} = workspace
      assert workspace.slug == LocalDefaults.default_workspace_slug()
      assert workspace.org_id == org.id
    end

    test "is idempotent: a second call reuses the same rows" do
      assert {:ok, {org1, ws1}} = LocalDefaults.ensure()
      assert {:ok, {org2, ws2}} = LocalDefaults.ensure()

      assert org1.id == org2.id
      assert ws1.id == ws2.id
    end

    test "errors when the default workspace belongs to a different org" do
      {:ok, other_org} = Accounts.create_org(%{name: "Other Org", slug: "other-org"})
      force_default_workspace(org_id: other_org.id)

      on_exit(&restore_default_workspace_ownership/0)

      assert {:error, {:workspace_org_conflict, ws_id, owned_by, default_org_id}} =
               LocalDefaults.ensure()

      assert owned_by == other_org.id

      default_org = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())
      assert default_org_id == default_org.id

      assert %{id: ^ws_id} =
               Repo.get_by(Workspace, slug: LocalDefaults.default_workspace_slug())
    end
  end

  describe "ensure/0 outside local mode" do
    test "is a no-op and creates no rows" do
      Application.put_env(:controlkeel, :local_defaults_local_mode_fn, fn -> false end)
      on_exit(fn -> Application.delete_env(:controlkeel, :local_defaults_local_mode_fn) end)

      before = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())

      assert {:ok, nil} = LocalDefaults.ensure()

      assert Accounts.get_org_by_slug(LocalDefaults.default_org_slug()) == before
    end
  end

  # Bring the default org + default workspace into existence, then force the
  # workspace into the requested org state for the scenario under test.
  defp force_default_workspace(org_id: org_id) do
    Accounts.create_org(%{
      name: "Default Organization",
      slug: LocalDefaults.default_org_slug()
    })

    case Repo.get_by(Workspace, slug: LocalDefaults.default_workspace_slug()) do
      nil ->
        Mission.create_workspace(%{
          name: "Default Workspace",
          slug: LocalDefaults.default_workspace_slug(),
          industry: "general",
          agent: "claude",
          budget_cents: 0,
          compliance_profile: "general",
          status: "active",
          org_id: org_id
        })

      %Workspace{} = workspace ->
        Mission.update_workspace(workspace, %{org_id: org_id})
    end
  end

  # Restore the cross-test invariant so a conflict scenario cannot leak into
  # other test files that share the test database.
  defp restore_default_workspace_ownership do
    default_org = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())

    case Repo.get_by(Workspace, slug: LocalDefaults.default_workspace_slug()) do
      nil ->
        :ok

      %Workspace{} = workspace when not is_nil(default_org) ->
        if workspace.org_id != default_org.id do
          Mission.update_workspace(workspace, %{org_id: default_org.id})
        end

      _ ->
        :ok
    end
  end
end
