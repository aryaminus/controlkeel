defmodule ControlKeel.CLITasksTest do
  use ControlKeel.DataCase

  import ExUnit.CaptureIO
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission
  alias ControlKeel.Analytics
  alias ControlKeel.Mission.Session
  alias ControlKeel.ProjectBinding
  alias ControlKeel.Repo

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-cli-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "ck.init creates project binding and is idempotent", %{tmp_dir: tmp_dir} do
    first_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.init")
        capture_io(fn -> Mix.Tasks.Ck.Init.run([]) end)
      end)

    assert first_output =~ "Initialized ControlKeel"

    assert {:ok, binding} = ProjectBinding.read(tmp_dir)

    assert Map.keys(binding) == [
             "agent",
             "attached_agents",
             "project_root",
             "session_id",
             "version",
             "workspace_id"
           ]

    assert binding["project_root"] == canonical_root(tmp_dir)
    assert binding["attached_agents"] == %{}
    assert File.read!(Path.join(tmp_dir, ".gitignore")) =~ "/controlkeel"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/bin/controlkeel-mcp"))

    session_count = Repo.aggregate(Session, :count, :id)

    second_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.init")
        capture_io(fn -> Mix.Tasks.Ck.Init.run([]) end)
      end)

    assert second_output =~ "already initialized"
    assert Repo.aggregate(Session, :count, :id) == session_count
  end

  test "ck.attach claude-code shells out and updates the binding", %{tmp_dir: tmp_dir} do
    create_claude_stub(tmp_dir, "controlkeel")

    with_project(tmp_dir, fn ->
      rerun_task("ck.init")
      Mix.Tasks.Ck.Init.run([])
    end)

    output =
      with_env("CONTROLKEEL_CLAUDE_BIN", Path.join(tmp_dir, "claude"), fn ->
        with_project(tmp_dir, fn ->
          rerun_task("ck.attach")
          capture_io(fn -> Mix.Tasks.Ck.Attach.run(["claude-code"]) end)
        end)
      end)

    assert output =~ "Attached ControlKeel to Claude Code."

    log = File.read!(Path.join(tmp_dir, "claude.log"))
    assert log =~ "mcp add-json controlkeel"
    assert log =~ "--scope local"
    assert log =~ "mcp get controlkeel"

    assert {:ok, binding} = ProjectBinding.read(tmp_dir)
    assert binding["attached_agents"]["claude_code"]["server_name"] == "controlkeel"
  end

  test "ck.attach fails clearly when claude is missing and does not mutate binding", %{
    tmp_dir: tmp_dir
  } do
    with_project(tmp_dir, fn ->
      rerun_task("ck.init")
      Mix.Tasks.Ck.Init.run([])
    end)

    assert_raise Mix.Error, ~r/Claude Code CLI was not found/, fn ->
      with_env("CONTROLKEEL_CLAUDE_BIN", Path.join(tmp_dir, "missing-claude"), fn ->
        with_project(tmp_dir, fn ->
          rerun_task("ck.attach")
          Mix.Tasks.Ck.Attach.run(["claude-code"])
        end)
      end)
    end

    assert {:ok, binding} = ProjectBinding.read(tmp_dir)
    assert binding["attached_agents"] == %{}
  end

  test "ck.status, ck.findings, and ck.approve operate on the bound local session", %{
    tmp_dir: tmp_dir
  } do
    session = session_fixture(%{budget_cents: 2_000, daily_budget_cents: 800, spent_cents: 350})
    open_finding = finding_fixture(%{session: session, status: "open", title: "Open finding"})

    _blocked_finding =
      finding_fixture(%{session: session, status: "blocked", title: "Blocked finding"})

    _approved_finding =
      finding_fixture(%{session: session, status: "approved", title: "Approved finding"})

    assert {:ok, _} =
             Analytics.record(%{
               event: "project_initialized",
               source: "test",
               session_id: session.id,
               workspace_id: session.workspace_id
             })

    write_binding(tmp_dir, session)

    status_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.status")
        capture_io(fn -> Mix.Tasks.Ck.Status.run([]) end)
      end)

    assert status_output =~ session.title
    assert status_output =~ "Budget:"
    assert status_output =~ "/proxy/openai/"
    assert status_output =~ "/proxy/anthropic/"
    assert status_output =~ "Funnel stage:"
    assert status_output =~ "Total findings:"
    assert status_output =~ "Blocked findings:"

    findings_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.findings")
        capture_io(fn -> Mix.Tasks.Ck.Findings.run(["--status", "open"]) end)
      end)

    assert findings_output =~ "Open finding"
    refute findings_output =~ "Approved finding"

    approve_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.approve")
        capture_io(fn -> Mix.Tasks.Ck.Approve.run([Integer.to_string(open_finding.id)]) end)
      end)

    assert approve_output =~ "Approved finding ##{open_finding.id}"
    assert Mission.get_finding!(open_finding.id).status == "approved"
  end

  defp write_binding(tmp_dir, session) do
    {:ok, _binding} =
      ProjectBinding.write(
        %{
          "workspace_id" => session.workspace_id,
          "session_id" => session.id,
          "agent" => "claude",
          "attached_agents" => %{}
        },
        tmp_dir
      )
  end

  defp create_claude_stub(tmp_dir, server_name) do
    stub = Path.join(tmp_dir, "claude")
    log = Path.join(tmp_dir, "claude.log")
    wrapper = Path.join(tmp_dir, "controlkeel/bin/controlkeel-mcp")

    File.write!(
      stub,
      """
      #!/bin/sh
      echo "$@" >> "#{log}"
      if [ "$1" = "mcp" ] && [ "$2" = "add-json" ]; then
        exit 0
      fi
      if [ "$1" = "mcp" ] && [ "$2" = "get" ]; then
        echo "#{server_name} #{wrapper}"
        exit 0
      fi
      echo "unsupported" >&2
      exit 1
      """
    )

    File.chmod!(stub, 0o755)
  end

  defp with_project(tmp_dir, fun), do: File.cd!(tmp_dir, fun)

  defp with_env(key, value, fun) do
    previous = System.get_env(key)

    try do
      System.put_env(key, value)
      fun.()
    after
      if previous, do: System.put_env(key, previous), else: System.delete_env(key)
    end
  end

  defp rerun_task(task_name) do
    Mix.Task.reenable(task_name)
  end

  defp canonical_root(path) do
    {realpath, 0} = System.cmd("/bin/pwd", ["-P"], cd: path, stderr_to_stdout: true)
    String.trim(realpath)
  end
end
