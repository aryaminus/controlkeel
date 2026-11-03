defmodule ControlKeel.CLITasksTest do
  use ControlKeel.DataCase

  import ControlKeel.BenchmarkFixtures
  import ExUnit.CaptureIO
  import ControlKeel.MissionFixtures

  alias ControlKeel.CLI
  alias ControlKeel.Mission
  alias ControlKeel.Analytics
  alias ControlKeel.Benchmark
  alias ControlKeel.Mission.Session
  alias ControlKeel.Project.Binding
  alias ControlKeel.Repo

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-cli-#{System.unique_integer([:positive])}")

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

    {:ok, tmp_dir: tmp_dir, home_dir: home_dir}
  end

  test "ck.init creates project binding and is idempotent", %{tmp_dir: tmp_dir} do
    first_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.init")
        capture_io(fn -> Mix.Tasks.Ck.Init.run([]) end)
      end)

    assert first_output =~ "Initialized ControlKeel"

    assert {:ok, binding} = Binding.read(tmp_dir)

    assert Map.keys(binding) == [
             "agent",
             "attached_agents",
             "bootstrap",
             "org_id",
             "project_root",
             "provider_override",
             "session_id",
             "tool_groups",
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

  test "ck.init auto-attaches when .claude dir exists and shim is available", %{
    tmp_dir: tmp_dir,
    home_dir: home_dir
  } do
    create_claude_shim(tmp_dir, "controlkeel")
    File.mkdir_p!(Path.join(home_dir, ".claude"))

    output =
      with_env("CONTROLKEEL_CLAUDE_BIN", Path.join(tmp_dir, "claude"), fn ->
        with_project(tmp_dir, fn ->
          rerun_task("ck.init")
          capture_io(fn -> Mix.Tasks.Ck.Init.run([]) end)
        end)
      end)

    assert output =~ "Initialized ControlKeel"
    assert output =~ "Attached ControlKeel to Claude Code."
  end

  test "ck.init --no-attach skips auto-attach and shows manual hint", %{tmp_dir: tmp_dir} do
    output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.init")
        capture_io(fn -> Mix.Tasks.Ck.Init.run(["--no-attach"]) end)
      end)

    assert output =~ "Initialized ControlKeel"
    assert output =~ "controlkeel attach claude-code"
    refute output =~ "Attached ControlKeel to Claude Code."
  end

  test "ck.attach claude-code shells out and updates the binding", %{tmp_dir: tmp_dir} do
    create_claude_shim(tmp_dir, "controlkeel")

    with_project(tmp_dir, fn ->
      rerun_task("ck.init")
      capture_io(fn -> Mix.Tasks.Ck.Init.run([]) end)
    end)

    output =
      with_env("CONTROLKEEL_CLAUDE_BIN", Path.join(tmp_dir, "claude"), fn ->
        with_project(tmp_dir, fn ->
          rerun_task("ck.attach")
          capture_io(fn -> Mix.Tasks.Ck.Attach.run(["claude-code"]) end)
        end)
      end)

    assert output =~ "Attached ControlKeel to Claude Code."

    # Phase 7 — attach should surface cloud-mode next steps so the user
    # discovers `cloud connect --enroll` and `cloud doctor` from the very
    # first attach output, not only by reading docs.
    assert output =~ "controlkeel cloud connect --enroll" or
             output =~ "Cloud — already connected"

    assert output =~ "controlkeel cloud doctor"

    log = File.read!(Path.join(tmp_dir, "claude.log"))
    assert log =~ "mcp add-json controlkeel"
    assert log =~ "--scope local"
    assert log =~ "mcp get controlkeel"

    assert {:ok, binding} = Binding.read(tmp_dir)
    assert binding["attached_agents"]["claude_code"]["server_name"] == "controlkeel"
  end

  test "ck.attach fails clearly when claude is missing and does not mutate binding", %{
    tmp_dir: tmp_dir
  } do
    with_project(tmp_dir, fn ->
      rerun_task("ck.init")
      capture_io(fn -> Mix.Tasks.Ck.Init.run([]) end)
    end)

    assert_raise Mix.Error, ~r/Claude Code CLI was not found/, fn ->
      with_env("CONTROLKEEL_CLAUDE_BIN", Path.join(tmp_dir, "missing-claude"), fn ->
        with_project(tmp_dir, fn ->
          rerun_task("ck.attach")
          capture_io(fn -> Mix.Tasks.Ck.Attach.run(["claude-code"]) end)
        end)
      end)
    end

    assert {:ok, binding} = Binding.read(tmp_dir)
    assert binding["attached_agents"] == %{}
  end

  test "ck.attach claude-code fails clearly when claude mcp reports failed to connect", %{
    tmp_dir: tmp_dir
  } do
    create_claude_shim_with_failed_connect(tmp_dir, "controlkeel")

    with_project(tmp_dir, fn ->
      rerun_task("ck.init")
      capture_io(fn -> Mix.Tasks.Ck.Init.run(["--no-attach"]) end)
    end)

    assert_raise Mix.Error, ~r/failed to connect|registered but failed to connect/i, fn ->
      with_env("CONTROLKEEL_CLAUDE_BIN", Path.join(tmp_dir, "claude"), fn ->
        with_project(tmp_dir, fn ->
          rerun_task("ck.attach")
          capture_io(fn -> Mix.Tasks.Ck.Attach.run(["claude-code"]) end)
        end)
      end)
    end

    assert {:ok, binding} = Binding.read(tmp_dir)
    assert binding["attached_agents"] == %{}
  end

  test "ck.status, ck.findings, and ck.approve operate on the bound local session", %{
    tmp_dir: tmp_dir
  } do
    proxy_token = "open" <> "ai"

    session =
      session_fixture(%{
        budget_cents: 2_000,
        daily_budget_cents: 800,
        spent_cents: 350,
        proxy_token: proxy_token
      })

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
    assert status_output =~ "/v1/completions"
    assert status_output =~ "/v1/embeddings"
    assert status_output =~ "/v1/models"
    assert status_output =~ "[REDACTED]"
    refute status_output =~ "/proxy/openai/#{session.proxy_token}/"
    refute status_output =~ "/proxy/anthropic/#{session.proxy_token}/"
    assert status_output =~ "Funnel stage:"
    assert status_output =~ "Total findings:"
    assert status_output =~ "Blocked findings:"

    status_json_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.status")
        capture_io(fn -> Mix.Tasks.Ck.Status.run(["--format", "json"]) end)
      end)

    assert String.starts_with?(status_json_output, "{")
    status_json = Jason.decode!(status_json_output)
    assert get_in(status_json, ["session", "id"]) == session.id
    assert get_in(status_json, ["session", "title"]) == session.title
    assert status_json_output =~ "[REDACTED]"
    refute status_json_output =~ "/proxy/openai/#{session.proxy_token}/"
    refute status_json_output =~ "/proxy/anthropic/#{session.proxy_token}/"

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

  test "ck.status auto-syncs stale attached agent bundles", %{tmp_dir: tmp_dir} do
    session = session_fixture()

    {:ok, _binding} =
      Binding.write(
        %{
          "workspace_id" => session.workspace_id,
          "session_id" => session.id,
          "agent" => "claude",
          "attached_agents" => %{
            "cursor" => %{
              "target" => "cursor-native",
              "scope" => "project",
              "controlkeel_version" => "0.0.1"
            }
          }
        },
        tmp_dir
      )

    status_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.status")
        capture_io(fn -> Mix.Tasks.Ck.Status.run([]) end)
      end)

    assert status_output =~ "Execution sandbox:"
    assert status_output =~ "Attached agents:"
    assert status_output =~ "cursor (CK v"

    assert {:ok, binding} = Binding.read(tmp_dir)
    assert binding["attached_agents"]["cursor"]["synced_at"]
    assert File.exists?(Path.join(tmp_dir, ".cursor/mcp.json"))
  end

  test "ck.proofs, ck.pause, ck.resume, and ck.memory.search operate on the bound session", %{
    tmp_dir: tmp_dir
  } do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "done", title: "Task with proof"})
    _proof = proof_bundle_fixture(%{task: task})

    _memory =
      memory_record_fixture(%{session: session, task_id: task.id, title: "Session memory"})

    write_binding(tmp_dir, session)

    proofs_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.proofs")
        capture_io(fn -> Mix.Tasks.Ck.Proofs.run([]) end)
      end)

    assert proofs_output =~ "Task with proof"

    memory_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.memory.search")
        capture_io(fn -> Mix.Tasks.Ck.Memory.Search.run(["Session"]) end)
      end)

    assert memory_output =~ "Session memory"

    task = task_fixture(%{session: session, status: "in_progress", title: "Pauseable task"})

    pause_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.pause")
        capture_io(fn -> Mix.Tasks.Ck.Pause.run([Integer.to_string(task.id)]) end)
      end)

    assert pause_output =~ "Paused task"

    resume_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.resume")
        capture_io(fn -> Mix.Tasks.Ck.Resume.run([Integer.to_string(task.id)]) end)
      end)

    assert resume_output =~ "Resumed task"
  end

  test "ck.skills delegates to the runtime skills CLI", %{tmp_dir: tmp_dir} do
    list_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.skills")
        capture_io(fn -> Mix.Tasks.Ck.Skills.run(["list"]) end)
      end)

    assert list_output =~ "controlkeel-governance"
    assert list_output =~ "targets:"

    export_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.skills")

        capture_io(fn ->
          Mix.Tasks.Ck.Skills.run(["export", "--target", "codex", "--project-root", tmp_dir])
        end)
      end)

    assert export_output =~ "Exported codex bundle."

    assert File.exists?(
             Path.join(tmp_dir, "controlkeel/dist/codex/.codex/agents/controlkeel-operator.toml")
           )

    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/codex/.codex/config.toml"))
  end

  test "skills doctor and token audit show actionable duplicate skill guidance", %{
    tmp_dir: tmp_dir
  } do
    assert {:ok, parsed_setup} = CLI.parse(["setup", "--project-root", tmp_dir])
    assert {:ok, _setup_lines} = CLI.run_command(parsed_setup, tmp_dir)

    skill_name = "shared-skill"

    # Identical copy in a second host dir: expected distribution (info, not warn).
    for {subdir, body_extra} <- [{".agents/skills", ""}, {".claude/skills", ""}] do
      skill_dir = Path.join([tmp_dir, subdir, skill_name])
      File.mkdir_p!(skill_dir)

      File.write!(
        Path.join(skill_dir, "SKILL.md"),
        """
        ---
        name: shared-skill
        description: Shared governance skill
        ---
        # Shared Skill

        Use CK governance for setup checks.#{body_extra}
        """
      )
    end

    assert {:ok, parsed_doctor} = CLI.parse(["skills", "doctor", "--project-root", tmp_dir])
    assert {:ok, doctor_lines} = CLI.run_command(parsed_doctor, tmp_dir)
    doctor_output = Enum.join(doctor_lines, "\n")

    # Identical cross-host copies are expected distribution: info line, no warning.
    assert doctor_output =~ "expected distribution"
    refute doctor_output =~ "SHADOWED SKILL COPIES"

    # A differing copy under the same name is real drift: warn + prune guidance.
    shadow_dir = Path.join([tmp_dir, ".cursor/skills", skill_name])
    File.mkdir_p!(shadow_dir)

    File.write!(
      Path.join(shadow_dir, "SKILL.md"),
      """
      ---
      name: shared-skill
      description: Divergent copy that shadows the preferred definition
      ---
      # Shared Skill (divergent)

      Different body content.
      """
    )

    assert {:ok, doctor_lines2} = CLI.run_command(parsed_doctor, tmp_dir)
    doctor_output2 = Enum.join(doctor_lines2, "\n")

    assert doctor_output2 =~ "SHADOWED SKILL COPIES"
    assert doctor_output2 =~ "controlkeel skills doctor --prune-duplicates"
    refute doctor_output2 =~ "controlkeel token audit --mode skills"

    assert {:ok, parsed_audit} =
             CLI.parse(["token", "audit", "--mode", "skills", "--project-root", tmp_dir])

    assert {:ok, audit_lines} = CLI.run_command(parsed_audit, tmp_dir)
    audit_output = Enum.join(audit_lines, "\n")

    assert audit_output =~ "Duplicate skill groups: 1"
    assert audit_output =~ "Duplicate skill tokens:"
    assert audit_output =~ "#{skill_name}: 3 copies"
    refute audit_output =~ "() tokens"
  end

  test "ck.benchmark delegates to the runtime benchmark CLI", %{tmp_dir: tmp_dir} do
    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "manual_subject",
        "label" => "Manual Subject",
        "type" => "manual_import"
      }
    ])

    list_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.benchmark")
        capture_io(fn -> Mix.Tasks.Ck.Benchmark.run(["list"]) end)
      end)

    assert list_output =~ "Benchmark suites:"
    assert list_output =~ "manual_subject"

    run_output =
      with_project(tmp_dir, fn ->
        rerun_task("ck.benchmark")

        capture_io(fn ->
          Mix.Tasks.Ck.Benchmark.run([
            "run",
            "--suite",
            "vibe_failures_v1",
            "--subjects",
            "controlkeel_validate",
            "--baseline-subject",
            "controlkeel_validate",
            "--scenario-slugs",
            "hardcoded_api_key_python_webhook",
            "--workspace-id",
            Integer.to_string(ControlKeel.BenchmarkFixtures.benchmark_workspace_id())
          ])
        end)
      end)

    assert run_output =~ "Benchmark run #"
    assert Benchmark.list_recent_runs(1) != []
  end

  test "ck.smoke runs through the benchmark engine without creating sessions" do
    session_count = Repo.aggregate(Session, :count, :id)

    output =
      capture_io(fn ->
        rerun_task("ck.smoke")
        Mix.Tasks.Ck.Smoke.run(["--host", "http://localhost:4000", "--scenario", "1"])
      end)

    assert output =~ "ControlKeel Benchmark"
    assert output =~ "BENCHMARK RESULTS"
    assert output =~ "/default-organization/workspaces/default-workspace/benchmarks/runs/"
    assert Repo.aggregate(Session, :count, :id) == session_count
  end

  defp write_binding(tmp_dir, session) do
    {:ok, _binding} =
      Binding.write(
        %{
          "workspace_id" => session.workspace_id,
          "session_id" => session.id,
          "agent" => "claude",
          "attached_agents" => %{}
        },
        tmp_dir
      )
  end

  defp create_claude_shim_with_failed_connect(tmp_dir, server_name) do
    shim = Path.join(tmp_dir, "claude")
    log = Path.join(tmp_dir, "claude.log")

    File.write!(
      shim,
      """
      #!/bin/sh
      echo "$@" >> "#{log}"
      if [ "$1" = "mcp" ] && [ "$2" = "add-json" ]; then
        exit 0
      fi
      if [ "$1" = "mcp" ] && [ "$2" = "get" ]; then
        echo "#{server_name}:"
        echo "  Scope: Local config"
        echo "  Status: ✗ Failed to connect"
        exit 0
      fi
      echo "unsupported" >&2
      exit 1
      """
    )

    File.chmod!(shim, 0o755)
  end

  defp create_claude_shim(tmp_dir, server_name) do
    shim = Path.join(tmp_dir, "claude")
    log = Path.join(tmp_dir, "claude.log")
    wrapper = Path.join(tmp_dir, "controlkeel/bin/controlkeel-mcp")

    File.write!(
      shim,
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

    File.chmod!(shim, 0o755)
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
    expanded = Path.expand(path)

    case :os.type() do
      {:win32, _} ->
        expanded

      _ ->
        case System.find_executable("pwd") do
          nil ->
            expanded

          executable ->
            {realpath, 0} = System.cmd(executable, ["-P"], cd: expanded, stderr_to_stdout: true)
            String.trim(realpath)
        end
    end
  end
end
