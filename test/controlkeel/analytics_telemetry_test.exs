defmodule ControlKeel.AnalyticsTelemetryTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Analytics.Event
  alias ControlKeel.Mission
  alias ControlKeel.ProjectBinding
  alias ControlKeel.Repo
  alias ControlKeel.Scanner

  setup do
    start_supervised!(ControlKeel.Analytics.TelemetryHandler)

    tmp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-analytics-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "local init records project_initialized", %{tmp_dir: tmp_dir} do
    with_project(tmp_dir, fn ->
      rerun_task("ck.init")
      Mix.Tasks.Ck.Init.run([])
    end)

    assert {:ok, binding} = ProjectBinding.read(tmp_dir)

    assert_eventually(fn ->
      Repo.get_by(Event, event: "project_initialized", session_id: binding["session_id"])
    end)
  end

  test "claude attach records agent_attached", %{tmp_dir: tmp_dir} do
    create_wrapper(tmp_dir)
    create_claude_stub(tmp_dir, "controlkeel")

    with_project(tmp_dir, fn ->
      rerun_task("ck.init")
      Mix.Tasks.Ck.Init.run([])
    end)

    with_env("CONTROLKEEL_CLAUDE_BIN", Path.join(tmp_dir, "claude"), fn ->
      with_project(tmp_dir, fn ->
        rerun_task("ck.attach")
        Mix.Tasks.Ck.Attach.run(["claude-code"])
      end)
    end)

    assert {:ok, binding} = ProjectBinding.read(tmp_dir)

    assert_eventually(fn ->
      Repo.get_by(Event, event: "agent_attached", session_id: binding["session_id"])
    end)
  end

  test "first finding is only recorded once per session" do
    session = session_fixture()

    scanner_finding = %Scanner.Finding{
      id: "scan-1",
      severity: "high",
      category: "security",
      rule_id: "security.sql_injection",
      decision: "block",
      plain_message: "Unsafe SQL concatenation is present.",
      location: %{"line" => 1},
      metadata: %{"scanner" => "fast_path"}
    }

    assert {:ok, _} =
             Mission.record_runtime_findings(session.id, [scanner_finding],
               session_id: session.id,
               scanner: "fast_path"
             )

    assert_eventually(fn ->
      Repo.get_by(Event, event: "first_finding_recorded", session_id: session.id)
    end)

    assert {:ok, _} =
             Mission.record_runtime_findings(session.id, [%{scanner_finding | id: "scan-2"}],
               session_id: session.id,
               scanner: "fast_path"
             )

    Process.sleep(50)

    assert Repo.aggregate(
             from(e in Event,
               where: e.event == "first_finding_recorded" and e.session_id == ^session.id
             ),
             :count,
             :id
           ) == 1
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(fun, 0) do
    assert fun.()
  end

  defp assert_eventually(fun, attempts) do
    case fun.() do
      nil ->
        Process.sleep(25)
        assert_eventually(fun, attempts - 1)

      false ->
        Process.sleep(25)
        assert_eventually(fun, attempts - 1)

      value ->
        assert value
    end
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

  defp create_wrapper(tmp_dir) do
    bin_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin_dir)
    path = Path.join(bin_dir, "controlkeel-mcp")
    File.write!(path, "#!/bin/sh\nexit 0\n")
    File.chmod!(path, 0o755)
  end

  defp create_claude_stub(tmp_dir, server_name) do
    stub = Path.join(tmp_dir, "claude")
    wrapper = Path.join(tmp_dir, "bin/controlkeel-mcp")

    File.write!(
      stub,
      """
      #!/bin/sh
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
end
