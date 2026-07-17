defmodule ControlKeel.MCP.Tools.CkMemoryToolsTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.{CkMemoryArchive, CkMemoryRecord, CkMemorySearch}
  alias ControlKeel.Project.Binding

  import ControlKeel.AccountsFixtures
  import ControlKeel.MissionFixtures

  test "memory tools accept current session from bound project and enforce task ownership" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ck-memory-current-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    session = session_fixture()
    task = task_fixture(%{session: session})

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => session.workspace_id,
                 "session_id" => session.id,
                 "agent" => "opencode",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    assert {:ok, recorded} =
             CkMemoryRecord.call(%{
               "session_id" => "current",
               "project_root" => tmp_dir,
               "task_id" => Integer.to_string(task.id),
               "memory" => "Continuation decision: use typed memory for host handoff.",
               "record_type" => "decision",
               "title" => "Continuation decision"
             })

    assert recorded["session_id"] == session.id
    assert recorded["task_id"] == task.id

    assert {:ok, search} =
             CkMemorySearch.call(%{
               "project_root" => tmp_dir,
               "query" => "host handoff",
               "top_k" => "5"
             })

    assert Enum.any?(search["records"], &(&1["id"] == recorded["memory_id"]))

    assert {:ok, archived} =
             CkMemoryArchive.call(%{
               "session_id" => "active",
               "project_root" => tmp_dir,
               "memory_id" => recorded["memory_id"]
             })

    assert archived["archived"] == true

    other_session = session_fixture()
    other_task = task_fixture(%{session: other_session})

    assert {:error, {:invalid_arguments, message}} =
             CkMemoryRecord.call(%{
               "session_id" => "current",
               "project_root" => tmp_dir,
               "task_id" => other_task.id,
               "memory" => "Wrong task"
             })

    assert message =~ "task_id"
    assert message =~ "current session"
  end

  test "memory tools reject invalid ids before writes" do
    assert {:error, {:invalid_arguments, message}} =
             CkMemoryRecord.call(%{
               "session_id" => "current",
               "task_id" => :nan,
               "memory" => "Nope"
             })

    assert message =~ "task_id"
    assert message =~ "integer"

    assert {:error, {:invalid_arguments, message}} =
             CkMemoryArchive.call(%{"session_id" => "current", "memory_id" => 1.5})

    assert message =~ "memory_id"
    assert message =~ "finite integer"
  end

  test "ck_memory_search detail_level=full returns body and metadata; compact omits them" do
    session = session_fixture()

    {:ok, record} =
      ControlKeel.Memory.record(%{
        workspace_id: session.workspace_id,
        session_id: session.id,
        record_type: "decision",
        title: "Verbosity knob",
        summary: "summary only",
        body: "full body contents here",
        tags: ["verbosity"],
        source_type: "test",
        source_id: "verbosity-1",
        metadata: %{"k" => "v"}
      })

    assert {:ok, compact} =
             CkMemorySearch.call(%{"session_id" => session.id, "query" => "verbosity"})

    compact_row = Enum.find(compact["records"], &(&1["id"] == record.id))
    assert compact["detail_level"] == "compact"
    assert compact_row
    refute Map.has_key?(compact_row, "body")
    refute Map.has_key?(compact_row, "metadata")

    assert {:ok, full} =
             CkMemorySearch.call(%{
               "session_id" => session.id,
               "query" => "verbosity",
               "detail_level" => "full"
             })

    full_row = Enum.find(full["records"], &(&1["id"] == record.id))
    assert full["detail_level"] == "full"
    assert full_row["body"] == "full body contents here"
    assert full_row["metadata"]["k"] == "v"
  end

  test "ck_memory_record is source-id idempotent and accepts visibility controls" do
    org = org_fixture()
    session = session_fixture()

    assert {:ok, first} =
             CkMemoryRecord.call(%{
               "session_id" => session.id,
               "memory" => "Original org-wide guidance",
               "record_type" => "decision",
               "title" => "Org guidance",
               "source_type" => "human_review",
               "source_id" => "guidance-1",
               "visibility" => "org",
               "shared_org_id" => org.id
             })

    assert {:ok, second} =
             CkMemoryRecord.call(%{
               "session_id" => session.id,
               "memory" => "Updated org-wide guidance",
               "record_type" => "decision",
               "title" => "Updated org guidance",
               "source_type" => "human_review",
               "source_id" => "guidance-1",
               "visibility" => "org",
               "shared_org_id" => org.id
             })

    assert second["memory_id"] == first["memory_id"]

    record = ControlKeel.Memory.get_record!(first["memory_id"])
    assert record.title == "Updated org guidance"
    assert record.visibility == "org"
    assert record.shared_org_id == org.id
  end
end
