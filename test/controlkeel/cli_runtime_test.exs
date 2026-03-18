defmodule ControlKeel.CLIRuntimeTest do
  use ControlKeel.DataCase

  import ExUnit.CaptureIO
  import ControlKeel.MissionFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.CLI
  alias ControlKeel.ProjectBinding

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-cli-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "parse defaults to serve and help/version render cleanly" do
    assert {:ok, %{command: :serve}} = CLI.parse([])

    help_output =
      capture_io(fn ->
        assert 0 == CLI.execute(%{command: :help, options: %{}, args: []})
      end)

    version_output =
      capture_io(fn ->
        assert 0 == CLI.execute(%{command: :version, options: %{}, args: []})
      end)

    assert help_output =~ "ControlKeel CLI"
    assert version_output =~ "ControlKeel"
  end

  test "runtime init and status use the packaged CLI path", %{tmp_dir: tmp_dir} do
    assert {:ok, init} = CLI.parse(["init"])
    init_output = capture_io(fn -> assert 0 == CLI.execute(init, project_root: tmp_dir) end)

    assert init_output =~ "Initialized ControlKeel"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/bin/controlkeel-mcp"))
    assert {:ok, _binding} = ProjectBinding.read(tmp_dir)

    session = session_fixture(%{title: "Runtime CLI session"})

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

    finding_fixture(%{session: session, status: "blocked", title: "Runtime blocked finding"})

    assert {:ok, _} =
             Analytics.record(%{
               event: "project_initialized",
               source: "test",
               session_id: session.id,
               workspace_id: session.workspace_id
             })

    assert {:ok, status} = CLI.parse(["status"])

    status_output =
      capture_io(fn ->
        assert 0 == CLI.execute(status, project_root: tmp_dir)
      end)

    assert status_output =~ "Runtime CLI session"
    assert status_output =~ "Blocked findings:"
  end

  test "mcp accepts --project-root explicitly", %{tmp_dir: tmp_dir} do
    assert {:ok, parsed} = CLI.parse(["mcp", "--project-root", tmp_dir])
    assert parsed.command == :mcp
    assert parsed.options[:project_root] == tmp_dir
  end
end
