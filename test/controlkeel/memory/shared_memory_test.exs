defmodule ControlKeel.Memory.SharedMemoryTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Memory.Record
  alias ControlKeel.Memory.Store.Sqlite
  alias ControlKeel.Repo

  import ControlKeel.AccountsFixtures
  import ControlKeel.MissionFixtures

  setup do
    org = org_fixture()
    ws1 = workspace_fixture(%{org_id: org.id})
    ws2 = workspace_fixture(%{org_id: org.id})
    {:ok, ws1: ws1, ws2: ws2, org: org}
  end

  defp insert_record(attrs) do
    session = session_fixture(%{workspace_id: attrs.workspace_id})

    Repo.insert!(%Record{
      workspace_id: attrs.workspace_id,
      session_id: session.id,
      record_type: "note",
      title: attrs[:title] || "test",
      summary: attrs[:summary] || "test summary",
      body: "",
      tags: [],
      source_type: "test",
      metadata: %{},
      visibility: attrs[:visibility] || "workspace",
      shared_org_id: attrs[:shared_org_id]
    })
  end

  describe "visibility: workspace (default)" do
    test "workspace-scoped search only returns own records", %{ws1: ws1, ws2: ws2} do
      insert_record(%{workspace_id: ws1.id, title: "ws1 private"})
      insert_record(%{workspace_id: ws2.id, title: "ws2 private"})

      result = Sqlite.search("private", workspace_id: ws1.id)
      ids = Enum.map(result.entries, & &1.workspace_id)
      assert Enum.all?(ids, &(&1 == ws1.id))
    end
  end

  describe "visibility: org" do
    test "org-scoped search returns own workspace + org-shared records", %{
      ws1: ws1,
      ws2: ws2,
      org: org
    } do
      insert_record(%{workspace_id: ws1.id, title: "ws1 private", visibility: "workspace"})

      insert_record(%{
        workspace_id: ws2.id,
        title: "org shared note",
        visibility: "org",
        shared_org_id: org.id
      })

      result = Sqlite.search("note", workspace_id: ws1.id, org_id: org.id, visibility: :org)
      titles = Enum.map(result.entries, & &1.title)
      assert "org shared note" in titles
    end

    test "org record from different org is not returned", %{ws1: ws1, ws2: ws2, org: org} do
      other_org = org_fixture()

      insert_record(%{
        workspace_id: ws2.id,
        title: "other org note",
        visibility: "org",
        shared_org_id: other_org.id
      })

      result = Sqlite.search("note", workspace_id: ws1.id, org_id: org.id, visibility: :org)
      titles = Enum.map(result.entries, & &1.title)
      refute "other org note" in titles
    end
  end

  describe "visibility: admin" do
    test "admin records are visible across orgs when searching with admin visibility", %{
      ws2: ws2
    } do
      insert_record(%{
        workspace_id: ws2.id,
        title: "admin-wide guideline",
        visibility: "admin",
        shared_org_id: nil
      })

      result = Sqlite.search("guideline", org_id: 1, visibility: :admin)
      titles = Enum.map(result.entries, & &1.title)
      assert "admin-wide guideline" in titles
    end
  end

  describe "record schema" do
    test "defaults to workspace visibility", %{ws1: ws1} do
      record = insert_record(%{workspace_id: ws1.id})
      assert record.visibility == "workspace"
      assert record.shared_org_id == nil
    end

    test "persists org visibility and shared_org_id", %{ws1: ws1, org: org} do
      record = insert_record(%{workspace_id: ws1.id, visibility: "org", shared_org_id: org.id})
      reloaded = Repo.get!(Record, record.id)
      assert reloaded.visibility == "org"
      assert reloaded.shared_org_id == org.id
    end
  end
end
