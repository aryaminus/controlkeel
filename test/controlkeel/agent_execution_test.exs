defmodule ControlKeel.AgentExecutionTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.AgentExecution
  alias ControlKeel.Mission
  alias ControlKeel.Platform

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-agent-execution-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      System.delete_env("CONTROLKEEL_EXECUTOR_CODEX_CLI_CMD")
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "embedded execution runs a configured direct command and completes the task", %{
    tmp_dir: tmp_dir
  } do
    session = session_fixture()
    task = task_fixture(%{session: session})

    script_path = Path.join(tmp_dir, "codex-executor.sh")

    File.write!(
      script_path,
      """
      #!/bin/sh
      cat > "$CONTROLKEEL_RESULT_PATH" <<'JSON'
      {"content":"def hello, do: :world","kind":"code"}
      JSON
      """
    )

    File.chmod!(script_path, 0o755)
    System.put_env("CONTROLKEEL_EXECUTOR_CODEX_CLI_CMD", script_path)

    assert {:ok, result} =
             AgentExecution.run_task(task.id,
               project_root: tmp_dir,
               agent: "codex-cli",
               mode: "embedded"
             )

    assert result["status"] == "done"
    assert File.exists?(Path.join(result["package_root"], "TASK.md"))
    assert File.exists?(Path.join(result["package_root"], "workspace_context.json"))
    assert File.exists?(Path.join(result["package_root"], "recent_events.json"))
    assert Mission.get_task(task.id).status == "verified"
    assert Mission.proof_summary_for_task(task.id)["deploy_ready"] in [true, false]
  end

  test "handoff execution creates hosted credentials and waits for callback", %{tmp_dir: tmp_dir} do
    session = session_fixture()
    task = task_fixture(%{session: session})

    assert {:ok, result} =
             AgentExecution.run_task(task.id,
               project_root: tmp_dir,
               agent: "cursor",
               mode: "handoff"
             )

    assert result["status"] == "waiting_callback"
    assert result["oauth_client_id"] =~ "ck-sa-"
    assert is_binary(result["client_secret"])
    assert File.exists?(Path.join(result["package_root"], "credentials.json"))
    assert File.exists?(Path.join(result["package_root"], "workspace_context.json"))
    assert File.exists?(Path.join(result["package_root"], "recent_events.json"))
    assert File.exists?(Path.join(result["bundle_path"], ".cursor/mcp.json"))
    assert Mission.get_task(task.id).status == "waiting_callback"
    assert Platform.list_service_accounts(session.workspace_id) != []
  end

  test "policy-gated execution blocks when the session has blocked findings", %{tmp_dir: tmp_dir} do
    session = session_fixture()
    _finding = finding_fixture(%{session: session, status: "blocked"})
    task = task_fixture(%{session: session})

    assert {:error, {:policy_blocked, reason}} =
             AgentExecution.run_task(task.id,
               project_root: tmp_dir,
               agent: "cursor",
               mode: "handoff"
             )

    assert reason =~ "human review"
    assert Mission.get_task(task.id).status == "blocked"
  end

  test "embedded execution tracks sandbox adapter in metadata", %{tmp_dir: tmp_dir} do
    session = session_fixture()
    task = task_fixture(%{session: session})

    script_path = Path.join(tmp_dir, "test-executor.sh")

    File.write!(
      script_path,
      """
      #!/bin/sh
      cat > "$CONTROLKEEL_RESULT_PATH" <<'JSON'
      {"status": "success", "message": "sandbox test"}
      JSON
      exit 0
      """
    )

    File.chmod!(script_path, 0o755)

    System.put_env("CONTROLKEEL_EXECUTOR_CODEX_CLI_CMD", script_path)

    {:ok, result} =
      AgentExecution.run_task(task.id,
        project_root: tmp_dir,
        agent: "codex-cli",
        mode: "embedded",
        sandbox: "local"
      )

    assert result["mode"] == "embedded"
    assert result["metadata"]["execution_sandbox"] == "local"
  end

  test "execution is blocked while a submitted plan review is pending", %{tmp_dir: tmp_dir} do
    session = session_fixture()
    task = task_fixture(%{session: session})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "submission_body" => "Pending approval"
             })

    assert {:error, {:review_pending, details}} =
             AgentExecution.run_task(task.id,
               project_root: tmp_dir,
               agent: "cursor",
               mode: "handoff"
             )

    assert details[:review_id] == review.id
    assert details[:review_status] == "pending"
  end
end
