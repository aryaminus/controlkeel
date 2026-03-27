defmodule ControlKeel.CLIRuntimeTest do
  use ControlKeel.DataCase

  import ControlKeel.BenchmarkFixtures
  import ExUnit.CaptureIO
  import ControlKeel.MissionFixtures
  import ControlKeel.PolicyTrainingFixtures
  import ControlKeel.PlatformFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.Benchmark
  alias ControlKeel.CLI
  alias ControlKeel.Platform
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

  test "attach writes companion artifacts and prints install guidance", %{tmp_dir: tmp_dir} do
    assert {:ok, init} = CLI.parse(["init", "--no-attach"])
    assert 0 == CLI.execute(init, project_root: tmp_dir)

    assert {:ok, codex_attach} = CLI.parse(["attach", "codex-cli", "--scope", "project"])

    codex_output =
      capture_io(fn ->
        assert 0 == CLI.execute(codex_attach, project_root: tmp_dir)
      end)

    assert codex_output =~ "Companion target: codex."
    assert codex_output =~ "@aryaminus/controlkeel"
    assert File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".codex/agents/controlkeel-operator.toml"))
    assert File.exists?(codex_config_path())

    assert {:ok, vscode_attach} = CLI.parse(["attach", "vscode"])

    vscode_output =
      capture_io(fn ->
        assert 0 == CLI.execute(vscode_attach, project_root: tmp_dir)
      end)

    assert vscode_output =~ "Prepared ControlKeel companion files for VS Code agent mode."
    assert vscode_output =~ "Companion target: github-repo."
    assert File.exists?(Path.join(tmp_dir, ".github/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".github/mcp.json"))
    assert File.exists?(Path.join(tmp_dir, ".vscode/mcp.json"))

    assert {:ok, cursor_attach} = CLI.parse(["attach", "cursor"])

    cursor_output =
      capture_io(fn ->
        assert 0 == CLI.execute(cursor_attach, project_root: tmp_dir)
      end)

    assert cursor_output =~ "Companion target: instructions-only."
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/instructions-only/AGENTS.md"))
    assert File.exists?(cursor_config_path())

    assert {:ok, hermes_attach} = CLI.parse(["attach", "hermes-agent", "--scope", "project"])

    hermes_output =
      capture_io(fn ->
        assert 0 == CLI.execute(hermes_attach, project_root: tmp_dir)
      end)

    assert hermes_output =~ "Prepared ControlKeel companion files for Hermes Agent."
    assert hermes_output =~ "Auth mode: config_reference."
    assert File.exists?(Path.join(tmp_dir, ".hermes/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".hermes/mcp.json"))

    assert {:ok, cline_attach} = CLI.parse(["attach", "cline"])

    cline_output =
      capture_io(fn ->
        assert 0 == CLI.execute(cline_attach, project_root: tmp_dir)
      end)

    assert cline_output =~ "Attached ControlKeel to Cline."
    assert cline_output =~ "Companion target: cline-native."
    assert cline_output =~ "Auth mode: ck_owned."
    assert File.exists?(cline_config_path())
    assert File.exists?(Path.join(tmp_dir, ".cline/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".clinerules/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".clinerules/workflows/controlkeel-review.md"))
  end

  test "bootstrap and provider commands work without manual init", %{tmp_dir: tmp_dir} do
    assert {:ok, provider_list} = CLI.parse(["provider", "list", "--project-root", tmp_dir])

    provider_list_output =
      capture_io(fn ->
        assert 0 == CLI.execute(provider_list, project_root: tmp_dir)
      end)

    assert provider_list_output =~ "Selected source: heuristic"

    assert {:ok, set_key} =
             CLI.parse(["provider", "set-key", "openai", "--value", "sk-cli-openai"])

    assert {:ok, set_base_url} =
             CLI.parse([
               "provider",
               "set-base-url",
               "openai",
               "--value",
               "http://127.0.0.1:1234/v1"
             ])

    assert {:ok, set_model} =
             CLI.parse(["provider", "set-model", "openai", "--value", "local-model"])

    assert {:ok, provider_default} =
             CLI.parse(["provider", "default", "openai", "--project-root", tmp_dir])

    assert 0 == CLI.execute(set_key, project_root: tmp_dir)
    assert 0 == CLI.execute(set_base_url, project_root: tmp_dir)
    assert 0 == CLI.execute(set_model, project_root: tmp_dir)
    assert 0 == CLI.execute(provider_default, project_root: tmp_dir)

    assert {:ok, provider_show} = CLI.parse(["provider", "show", "--project-root", tmp_dir])

    provider_show_output =
      capture_io(fn ->
        assert 0 == CLI.execute(provider_show, project_root: tmp_dir)
      end)

    assert provider_show_output =~ "Selected source: user_default_profile"
    assert provider_show_output =~ "Selected provider: openai"
    assert provider_show_output =~ "Selected base URL: http://127.0.0.1:1234/v1"

    assert {:ok, attach} = CLI.parse(["attach", "cursor"])

    attach_output =
      capture_io(fn ->
        assert 0 == CLI.execute(attach, project_root: tmp_dir)
      end)

    assert attach_output =~ "Bootstrap mode: project."
    assert File.exists?(Path.join(tmp_dir, "controlkeel/project.json"))
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/instructions-only/AGENTS.md"))

    assert {:ok, bootstrap} = CLI.parse(["bootstrap", "--project-root", tmp_dir])

    bootstrap_output =
      capture_io(fn ->
        assert 0 == CLI.execute(bootstrap, project_root: tmp_dir)
      end)

    assert bootstrap_output =~ "Bootstrapped ControlKeel"
    assert bootstrap_output =~ "Binding mode: existing"
  end

  test "runtime export emits the Open SWE headless bundle", %{tmp_dir: tmp_dir} do
    assert {:ok, export} = CLI.parse(["runtime", "export", "open-swe", "--project-root", tmp_dir])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(export, project_root: tmp_dir)
      end)

    assert output =~ "Prepared Open SWE runtime export."
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/open-swe-runtime/AGENTS.md"))

    assert File.exists?(
             Path.join(tmp_dir, "controlkeel/dist/open-swe-runtime/open-swe/README.md")
           )
  end

  test "runtime export emits the Devin headless bundle", %{tmp_dir: tmp_dir} do
    assert {:ok, export} = CLI.parse(["runtime", "export", "devin", "--project-root", tmp_dir])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(export, project_root: tmp_dir)
      end)

    assert output =~ "Prepared Devin runtime export."
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/devin-runtime/AGENTS.md"))
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/devin-runtime/devin/README.md"))

    assert File.exists?(
             Path.join(tmp_dir, "controlkeel/dist/devin-runtime/devin/controlkeel-mcp.json")
           )
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

  test "runtime platform commands manage service accounts, graphs, and audit exports", %{
    tmp_dir: tmp_dir
  } do
    previous_renderer = Application.get_env(:controlkeel, :pdf_renderer)
    Application.put_env(:controlkeel, :pdf_renderer, ControlKeel.TestSupport.FakePdfRenderer)

    on_exit(fn ->
      if previous_renderer do
        Application.put_env(:controlkeel, :pdf_renderer, previous_renderer)
      else
        Application.delete_env(:controlkeel, :pdf_renderer)
      end
    end)

    workspace = workspace_fixture()
    session = session_fixture(%{workspace: workspace})

    _arch =
      task_fixture(%{
        session: session,
        status: "done",
        position: 1,
        metadata: %{"track" => "architecture"}
      })

    _feature =
      task_fixture(%{
        session: session,
        status: "queued",
        position: 2,
        metadata: %{"track" => "feature"}
      })

    _release =
      task_fixture(%{
        session: session,
        status: "queued",
        position: 3,
        metadata: %{"track" => "release"}
      })

    account_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{
                     command: :service_account_create,
                     options: [
                       workspace_id: workspace.id,
                       name: "Runner",
                       scopes: "tasks:claim,tasks:report"
                     ],
                     args: []
                   },
                   project_root: tmp_dir
                 )
      end)

    assert account_output =~ "Created service account"

    graph_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{command: :graph_show, options: %{}, args: [Integer.to_string(session.id)]},
                   project_root: tmp_dir
                 )
      end)

    assert graph_output =~ "Task graph for session"

    execute_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{
                     command: :execute_session,
                     options: %{},
                     args: [Integer.to_string(session.id)]
                   },
                   project_root: tmp_dir
                 )
      end)

    assert execute_output =~ "Executed scheduling"

    audit_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{
                     command: :audit_log,
                     options: [format: "pdf"],
                     args: [Integer.to_string(session.id)]
                   },
                   project_root: tmp_dir
                 )
      end)

    assert audit_output =~ "Artifact:"

    policy_set = policy_set_fixture()

    apply_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{
                     command: :policy_set_apply,
                     options: [precedence: 5],
                     args: [Integer.to_string(workspace.id), Integer.to_string(policy_set.id)]
                   },
                   project_root: tmp_dir
                 )
      end)

    assert apply_output =~ "Applied policy set"

    assert Platform.list_workspace_policy_sets(workspace.id) != []
  end

  defp codex_config_path do
    home = System.get_env("HOME") || System.user_home!()

    case :os.type() do
      {:win32, _} -> Path.join([System.get_env("APPDATA") || home, ".codex", "config.json"])
      _ -> Path.join([home, ".codex", "config.json"])
    end
  end

  defp cursor_config_path do
    home = System.get_env("HOME") || System.user_home!()

    case :os.type() do
      {:win32, _} ->
        Path.join([
          System.get_env("APPDATA") || home,
          "Cursor",
          "User",
          "globalStorage",
          "cursor.mcp.json"
        ])

      {:unix, :darwin} ->
        Path.join([
          home,
          "Library",
          "Application Support",
          "Cursor",
          "User",
          "globalStorage",
          "cursor.mcp.json"
        ])

      _ ->
        Path.join([home, ".config", "Cursor", "User", "globalStorage", "cursor.mcp.json"])
    end
  end

  defp cline_config_path do
    base =
      System.get_env("CLINE_DIR") ||
        Path.join(System.get_env("HOME") || System.user_home!(), ".cline")

    Path.join([base, "data", "settings", "cline_mcp_settings.json"])
  end
end
