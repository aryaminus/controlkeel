defmodule ControlKeel.CLIRuntimeTest do
  use ControlKeel.DataCase

  import ControlKeel.BenchmarkFixtures
  import ExUnit.CaptureIO
  import ControlKeel.MissionFixtures
  import ControlKeel.PolicyTrainingFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.Benchmark
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
    home_dir = Path.join(tmp_dir, "home")
    File.mkdir_p!(home_dir)

    previous_home = System.get_env("HOME")
    System.put_env("HOME", home_dir)

    on_exit(fn ->
      if previous_home do
        System.put_env("HOME", previous_home)
      else
        System.delete_env("HOME")
      end

      File.rm_rf!(tmp_dir)
    end)

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

  test "runtime proofs, pause, resume, and memory search operate on the bound session", %{
    tmp_dir: tmp_dir
  } do
    session = session_fixture(%{title: "CLI proof session"})
    task = task_fixture(%{session: session, status: "done", title: "CLI proof task"})
    _proof = proof_bundle_fixture(%{task: task})
    _memory = memory_record_fixture(%{session: session, task_id: task.id, title: "CLI memory"})

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

    proofs_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :proofs, options: %{}, args: []}, project_root: tmp_dir)
      end)

    assert proofs_output =~ "CLI proof task"

    memory_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{command: :memory_search, options: %{}, args: ["CLI memory"]},
                   project_root: tmp_dir
                 )
      end)

    assert memory_output =~ "CLI memory"

    task = task_fixture(%{session: session, status: "in_progress", title: "Pause me"})

    pause_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{command: :pause, options: %{}, args: [Integer.to_string(task.id)]},
                   project_root: tmp_dir
                 )
      end)

    assert pause_output =~ "Paused task"

    resume_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{command: :resume, options: %{}, args: [Integer.to_string(task.id)]},
                   project_root: tmp_dir
                 )
      end)

    assert resume_output =~ "Resumed task"
  end

  test "runtime benchmark commands list, run, show, import, and export", %{tmp_dir: tmp_dir} do
    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "manual_subject",
        "label" => "Manual Subject",
        "type" => "manual_import"
      }
    ])

    assert {:ok, list} = CLI.parse(["benchmark", "list", "--domain-pack", "hr"])

    list_output =
      capture_io(fn ->
        assert 0 == CLI.execute(list, project_root: tmp_dir)
      end)

    assert list_output =~ "Benchmark suites:"
    assert list_output =~ "manual_subject"
    assert list_output =~ "domain_expansion_v1"
    refute list_output =~ "vibe_failures_v1"

    assert {:ok, run_command} =
             CLI.parse([
               "benchmark",
               "run",
               "--suite",
               "domain_expansion_v1",
               "--subjects",
               "controlkeel_validate",
               "--baseline-subject",
               "controlkeel_validate",
               "--domain-pack",
               "sales"
             ])

    run_output =
      capture_io(fn ->
        assert 0 == CLI.execute(run_command, project_root: tmp_dir)
      end)

    assert run_output =~ "Benchmark run #"
    assert run_output =~ "Domains: Sales / CRM"

    run = Benchmark.list_recent_runs(1) |> List.first()
    assert run

    assert {:ok, show} = CLI.parse(["benchmark", "show", Integer.to_string(run.id)])

    show_output =
      capture_io(fn ->
        assert 0 == CLI.execute(show, project_root: tmp_dir)
      end)

    assert show_output =~ "Benchmark run ##{run.id}"
    assert show_output =~ "Catch rate:"

    assert {:ok, export} =
             CLI.parse(["benchmark", "export", Integer.to_string(run.id), "--format", "csv"])

    export_output =
      capture_io(fn ->
        assert 0 == CLI.execute(export, project_root: tmp_dir)
      end)

    assert export_output =~ "run_id,suite_slug,scenario_slug"

    {:ok, manual_run} =
      Benchmark.run_suite(
        %{
          "suite" => "vibe_failures_v1",
          "subjects" => "manual_subject",
          "baseline_subject" => "manual_subject",
          "scenario_slugs" => "client_side_auth_bypass"
        },
        tmp_dir
      )

    import_path = Path.join(tmp_dir, "manual-import.json")

    File.write!(
      import_path,
      Jason.encode!(%{
        "scenario_slug" => "client_side_auth_bypass",
        "content" => "document.getElementById('admin-panel').innerHTML = userInput;",
        "path" => "assets/js/admin.js",
        "kind" => "code",
        "duration_ms" => 16
      })
    )

    assert {:ok, import_command} =
             CLI.parse([
               "benchmark",
               "import",
               Integer.to_string(manual_run.id),
               "manual_subject",
               import_path
             ])

    import_output =
      capture_io(fn ->
        assert 0 == CLI.execute(import_command, project_root: tmp_dir)
      end)

    assert import_output =~ "Imported benchmark output for manual_subject"
  end

  test "runtime policy commands list, train, show, promote, and archive" do
    benchmark_run_fixture(%{
      "suite" => "vibe_failures_v1",
      "subjects" => "controlkeel_validate",
      "baseline_subject" => "controlkeel_validate",
      "scenario_slugs" => "hardcoded_api_key_python_webhook"
    })

    list_output =
      capture_io(fn ->
        assert 0 == CLI.execute(%{command: :policy_list, options: %{}, args: []})
      end)

    assert list_output =~ "Active artifacts:"

    train_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{
                   command: :policy_train,
                   options: [type: "router"],
                   args: []
                 })
      end)

    assert train_output =~ "Policy artifact"

    artifact = policy_artifact_fixture(%{artifact_type: "budget_hint"})

    show_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{
                   command: :policy_show,
                   options: %{},
                   args: [Integer.to_string(artifact.id)]
                 })
      end)

    assert show_output =~ "Policy artifact ##{artifact.id}"

    promotable =
      policy_artifact_fixture(%{
        artifact_type: "router",
        metrics: %{"gates" => %{"eligible" => true, "reasons" => []}}
      })

    promote_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{
                   command: :policy_promote,
                   options: %{},
                   args: [Integer.to_string(promotable.id)]
                 })
      end)

    assert promote_output =~ "Promoted policy artifact"

    archive_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{
                   command: :policy_archive,
                   options: %{},
                   args: [Integer.to_string(promotable.id)]
                 })
      end)

    assert archive_output =~ "Archived policy artifact"
  end
end
