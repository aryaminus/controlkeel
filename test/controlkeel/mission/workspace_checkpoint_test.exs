defmodule ControlKeel.Mission.WorkspaceCheckpointTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Mission
  alias ControlKeel.Mission.WorkspaceCheckpoint

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-workspace-checkpoint-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    File.write!(Path.join(tmp_dir, "README.md"), "# Trial\n")

    assert {_, 0} = System.cmd("git", ["init"], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["add", "."], cd: tmp_dir)
    assert {_, 0} = System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    workspace_attrs = %{
      name: "Demo",
      slug: "trial-#{System.unique_integer([:positive])}",
      industry: "software",
      agent: "test",
      budget_cents: 0,
      compliance_profile: "none",
      status: "active",
      org_id: ControlKeel.AccountsFixtures.org_fixture().id
    }

    assert {:ok, workspace} = Mission.create_workspace(workspace_attrs)

    session_attrs = %{
      title: "Test session",
      objective: "Test",
      risk_tier: "low",
      status: "planned",
      budget_cents: 0,
      daily_budget_cents: 0,
      spent_cents: 0,
      execution_brief: %{},
      metadata: %{"runtime_context" => %{"project_root" => tmp_dir}},
      workspace_id: workspace.id
    }

    assert {:ok, session} = Mission.create_session(session_attrs)

    task_attrs = %{
      title: "Checkpoint task",
      status: "queued",
      estimated_cost_cents: 0,
      validation_gate: "none",
      position: 0,
      metadata: %{},
      session_id: session.id
    }

    assert {:ok, task} = Mission.create_task(task_attrs)

    %{tmp_dir: tmp_dir, session: session, task: task}
  end

  test "create/3 stores a checkpoint and returns workspace hash", %{session: session, task: task} do
    assert {:ok, result} =
             WorkspaceCheckpoint.create(session.id, task.id,
               type: "workspace_snapshot",
               summary: "snap"
             )

    assert is_integer(result["id"])
    assert result["checkpoint_type"] == "workspace_snapshot"
    assert result["summary"] == "snap"
    assert is_binary(get_in(result, ["workspace_state", "workspace_hash"]))
  end

  test "restore/3 annotates session metadata", %{session: session, task: task} do
    assert {:ok, created} = WorkspaceCheckpoint.create(session.id, task.id, summary: "snap")

    assert {:ok, restore_result} =
             WorkspaceCheckpoint.restore(session.id, created["id"], strict: false)

    assert restore_result["checkpoint_id"] == created["id"]

    updated = Mission.get_session!(session.id)
    restored = get_in(updated.metadata, ["restored_from_checkpoint"]) || %{}
    assert restored["checkpoint_id"] == created["id"]
  end
end
