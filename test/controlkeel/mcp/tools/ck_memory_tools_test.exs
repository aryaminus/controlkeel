defmodule ControlKeel.MCP.Tools.CkMemoryToolsTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.{CkMemoryArchive, CkMemoryRecord, CkMemorySearch}
  alias ControlKeel.ProjectBinding

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
             ProjectBinding.write(
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
end
