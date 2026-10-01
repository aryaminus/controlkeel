defmodule ControlKeel.CLI.NewCommandsTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures
  import ExUnit.CaptureIO

  alias ControlKeel.Benchmark.Run
  alias ControlKeel.CLI
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Invocation, SessionEvent}
  alias ControlKeel.Observability.ImportedEnvelope
  alias ControlKeel.Repo
  alias ControlKeel.Mission.ReviewBridge
  alias ControlKeel.Project.Binding
  alias ControlKeel.Learning.OutcomeTracker

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-new-cli-#{System.unique_integer([:positive])}")

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

  # Unwrap the CLI success envelope for test assertions.
  # The execute/1 interceptor wraps all JSON output in:
  #   {"status" => "ok", "command" => "...", "data" => <payload>, "version" => "..."}
  # This helper extracts the data payload so tests can assert on the original structure.
  defp decode_cli_json(output) do
    decoded = Jason.decode!(output)

    case decoded do
      %{"status" => "ok", "data" => data} -> data
      %{"status" => "error"} -> decoded
      other -> other
    end
  end

  describe "deploy commands" do
    test "deploy analyze parses and runs", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule My.App do\nuse Mix.Project\nend")
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.write!(Path.join(tmp_dir, "lib/app.ex"), "defmodule My.App do\nuse Phoenix\nend")

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :deploy_analyze, options: %{project_root: tmp_dir}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Stack:"
      assert output =~ "Compatible platforms:"
    end

    test "deploy cost parses and runs" do
      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :deploy_cost,
                       options: %{stack: "phoenix", tier: "free"},
                       args: []
                     },
                     project_root: "."
                   )
        end)

      assert output =~ "Hosting cost estimates"
    end

    test "deploy dns shows dns and ssl guide" do
      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :deploy_dns, options: %{stack: "phoenix"}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "DNS Setup for phoenix"
      assert output =~ "SSL Setup"
    end

    test "deploy migration shows migration guide" do
      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :deploy_migration, options: %{stack: "phoenix"}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "Database Migration Guide for phoenix"
    end

    test "deploy scaling shows scaling guide" do
      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :deploy_scaling, options: %{stack: "phoenix"}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "Scaling Guide for phoenix"
      assert output =~ "Vertical Scaling"
    end

    test "deploy commands parse correctly" do
      assert {:ok, %{command: :deploy_analyze}} = CLI.parse(["deploy", "analyze"])
      assert {:ok, %{command: :deploy_cost}} = CLI.parse(["deploy", "cost"])
      assert {:ok, %{command: :deploy_dns}} = CLI.parse(["deploy", "dns", "phoenix"])
      assert {:ok, %{command: :deploy_migration}} = CLI.parse(["deploy", "migration", "rails"])
      assert {:ok, %{command: :deploy_scaling}} = CLI.parse(["deploy", "scaling", "node"])
    end

    test "deploy cost with all options" do
      assert {:ok, parsed} =
               CLI.parse([
                 "deploy",
                 "cost",
                 "--stack",
                 "react",
                 "--tier",
                 "pro",
                 "--needs-db",
                 "--bandwidth",
                 "50",
                 "--storage",
                 "10"
               ])

      assert parsed.command == :deploy_cost
      assert parsed.options[:stack] == "react"
      assert parsed.options[:tier] == "pro"
      assert parsed.options[:needs_db] == true
      assert parsed.options[:bandwidth] == 50
      assert parsed.options[:storage] == 10
    end
  end

  describe "watch command" do
    test "watch command parses interval and status switches" do
      assert {:ok, %{command: :watch}} = CLI.parse(["watch"])

      assert {:ok, parsed} = CLI.parse(["watch", "--interval", "1500"])
      assert parsed.options[:interval] == 1500

      assert {:ok, parsed_status} = CLI.parse(["watch", "--status"])
      assert parsed_status.options[:status] == true
    end

    test "watch --status runs one-shot status output", %{tmp_dir: tmp_dir} do
      session = session_fixture(%{budget_cents: 2_000, daily_budget_cents: 800, spent_cents: 350})
      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :watch, options: %{status: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Session: "
      assert output =~ "Risk tier:"
      assert output =~ "Suggested next steps:"
    end
  end

  describe "cost commands" do
    test "cost optimize runs without session" do
      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :cost_optimize, options: %{}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "cost optimization" || output =~ "No cost optimization"
    end

    test "cost compare runs with default tokens" do
      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :cost_compare, options: %{}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "Agent cost comparison"
    end

    test "cost compare with custom tokens" do
      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :cost_compare, options: %{tokens: 50_000}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "50000 tokens"
    end

    test "cost commands parse correctly" do
      assert {:ok, %{command: :cost_optimize}} = CLI.parse(["cost", "optimize"])
      assert {:ok, %{command: :cost_compare}} = CLI.parse(["cost", "compare"])

      assert {:ok, parsed} =
               CLI.parse(["cost", "optimize", "--session-id", "42", "--provider", "openai"])

      assert parsed.command == :cost_optimize
      assert parsed.options[:session_id] == 42
    end
  end

  test "top-level help and version flags parse" do
    assert {:ok, %{command: :help}} = CLI.parse(["--help"])
    assert {:ok, %{command: :help}} = CLI.parse(["-h"])
    assert {:ok, %{command: :version}} = CLI.parse(["--version"])
    assert {:ok, %{command: :version}} = CLI.parse(["-V"])
    assert {:ok, %{command: :version}} = CLI.parse(["-v"])
    assert {:ok, %{command: :attach_doctor}} = CLI.parse(["attach", "doctor"])
  end

  describe "review plan commands" do
    test "parse review plan subcommands" do
      assert {:ok, %{command: :review_plan_submit}} =
               CLI.parse(["review", "plan", "submit", "--stdin"])

      assert {:ok, %{command: :review_plan_open, options: [id: 42]}} =
               CLI.parse(["review", "plan", "open", "--id", "42"])

      assert {:ok, %{command: :review_plan_wait, options: [id: 42]}} =
               CLI.parse(["review", "plan", "wait", "--id", "42"])

      assert {:ok, %{command: :review_plan_respond, args: ["9"]}} =
               CLI.parse(["review", "plan", "respond", "9", "--decision", "approved"])
    end

    test "submit, open, wait, and respond work end-to-end", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      task = task_fixture(%{session: session})
      plan_path = Path.join(tmp_dir, "plan.md")
      File.write!(plan_path, "1. Draft implementation\n2. Request approval")

      assert {:ok, submit_lines} =
               CLI.run_command(
                 %{
                   command: :review_plan_submit,
                   options: %{task_id: task.id, body_file: plan_path},
                   args: []
                 },
                 tmp_dir
               )

      assert Enum.any?(submit_lines, &String.contains?(&1, "Submitted plan review"))

      review = ControlKeel.Mission.latest_review_for_task(task.id, "plan")

      assert {:ok, open_lines} =
               CLI.run_command(
                 %{command: :review_plan_open, options: %{id: review.id}, args: []},
                 tmp_dir
               )

      assert Enum.any?(
               open_lines,
               &String.contains?(&1, "/sessions/#{review.session_id}/reviews/#{review.id}")
             )

      assert Enum.any?(open_lines, &String.contains?(&1, "Review server serving:"))
      assert Enum.any?(open_lines, &String.contains?(&1, "Opened browser: false"))

      assert Enum.any?(
               open_lines,
               &String.contains?(&1, "ask the user for explicit approval")
             )

      assert {:ok, respond_lines} =
               CLI.run_command(
                 %{
                   command: :review_plan_respond,
                   options: %{decision: "approved", feedback_notes: "Ship it"},
                   args: [Integer.to_string(review.id)]
                 },
                 tmp_dir
               )

      assert Enum.any?(respond_lines, &String.contains?(&1, "Status: approved"))

      assert {:ok, wait_lines} =
               CLI.run_command(
                 %{command: :review_plan_wait, options: %{id: review.id, timeout: 1}, args: []},
                 tmp_dir
               )

      assert Enum.any?(wait_lines, &String.contains?(&1, "approved"))
    end

    test "submit honors --project-root when cwd is elsewhere", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      _task = task_fixture(%{session: session})
      write_binding(tmp_dir, session)

      plan_path = Path.join(tmp_dir, "plan.md")
      File.write!(plan_path, "1. Submit with explicit project root")

      outside_dir = Path.join(tmp_dir, "outside")
      File.mkdir_p!(outside_dir)
      previous_cwd = File.cwd!()
      File.cd!(outside_dir)

      on_exit(fn ->
        File.cd!(previous_cwd)
      end)

      assert {:ok, [submit_json]} =
               CLI.run_command(
                 %{
                   command: :review_plan_submit,
                   options: %{body_file: plan_path, project_root: tmp_dir, json: true},
                   args: []
                 },
                 outside_dir
               )

      payload = decode_cli_json(submit_json)
      assert get_in(payload, ["review", "session_id"]) == session.id
      assert is_integer(get_in(payload, ["review", "id"]))
    end

    test "submit infers task scope from project binding when ids are missing", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      task = task_fixture(%{session: session})
      plan_path = Path.join(tmp_dir, "plan.md")
      File.write!(plan_path, "1. Infer scope from binding")
      write_binding(tmp_dir, session)

      assert {:ok, [submit_json]} =
               CLI.run_command(
                 %{
                   command: :review_plan_submit,
                   options: %{body_file: plan_path, json: true},
                   args: []
                 },
                 tmp_dir
               )

      payload = decode_cli_json(submit_json)
      review_id = get_in(payload, ["review", "id"])

      assert is_integer(review_id)
      assert get_in(payload, ["review", "task_id"]) == task.id
      assert get_in(payload, ["review", "session_id"]) == session.id
      assert get_in(payload, ["review", "status"]) == "pending"
    end

    test "submit supports env-inferred runtime context and json payloads", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      task = task_fixture(%{session: session})
      plan_path = Path.join(tmp_dir, "plan.md")
      File.write!(plan_path, "1. Explore runtime-backed submission")

      {:ok, _task} =
        Mission.attach_task_runtime_context(task.id, %{
          "agent_id" => "opencode",
          "thread_id" => "thread-123"
        })

      previous_agent_id = System.get_env("CONTROLKEEL_AGENT_ID")
      previous_thread_id = System.get_env("CONTROLKEEL_THREAD_ID")
      previous_remote = System.get_env("CONTROLKEEL_REMOTE")

      System.put_env("CONTROLKEEL_AGENT_ID", "opencode")
      System.put_env("CONTROLKEEL_THREAD_ID", "thread-123")
      System.put_env("CONTROLKEEL_REMOTE", "1")

      on_exit(fn ->
        if previous_agent_id,
          do: System.put_env("CONTROLKEEL_AGENT_ID", previous_agent_id),
          else: System.delete_env("CONTROLKEEL_AGENT_ID")

        if previous_thread_id,
          do: System.put_env("CONTROLKEEL_THREAD_ID", previous_thread_id),
          else: System.delete_env("CONTROLKEEL_THREAD_ID")

        if previous_remote,
          do: System.put_env("CONTROLKEEL_REMOTE", previous_remote),
          else: System.delete_env("CONTROLKEEL_REMOTE")
      end)

      assert {:ok, [submit_json]} =
               CLI.run_command(
                 %{
                   command: :review_plan_submit,
                   options: %{body_file: plan_path, json: true},
                   args: []
                 },
                 tmp_dir
               )

      payload = decode_cli_json(submit_json)
      review_id = get_in(payload, ["review", "id"])

      assert is_integer(review_id)
      assert get_in(payload, ["review", "task_id"]) == task.id
      assert payload["browser_url"] =~ "/sessions/#{session.id}/reviews/#{review_id}"

      assert {:ok, [open_json]} =
               CLI.run_command(
                 %{command: :review_plan_open, options: %{id: review_id, json: true}, args: []},
                 tmp_dir
               )

      open_payload = decode_cli_json(open_json)
      assert open_payload["browser_url"] =~ "/sessions/#{session.id}/reviews/#{review_id}"
      assert open_payload["open_target"] == "manual"
      assert open_payload["opened"] == false
      assert open_payload["remote"] == true
      assert is_boolean(open_payload["server_serving"])

      if open_payload["server_serving"] == false do
        assert is_binary(open_payload["server_error"])
      end

      assert {:ok, _respond_lines} =
               CLI.run_command(
                 %{
                   command: :review_plan_respond,
                   options: %{decision: "approved", feedback_notes: "Proceed", json: true},
                   args: [Integer.to_string(review_id)]
                 },
                 tmp_dir
               )

      assert {:ok, [wait_json]} =
               CLI.run_command(
                 %{
                   command: :review_plan_wait,
                   options: %{id: review_id, timeout: 1, json: true},
                   args: []
                 },
                 tmp_dir
               )

      wait_payload = decode_cli_json(wait_json)
      assert get_in(wait_payload, ["review", "status"]) == "approved"
    end

    test "denied review json includes strong agent feedback guidance", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      task = task_fixture(%{session: session})
      plan_path = Path.join(tmp_dir, "PLAN.md")
      File.write!(plan_path, "# Plan\n\n1. Do the work")

      assert {:ok, [submit_json]} =
               CLI.run_command(
                 %{
                   command: :review_plan_submit,
                   options: %{task_id: task.id, body_file: plan_path, json: true},
                   args: []
                 },
                 tmp_dir
               )

      review_id = get_in(decode_cli_json(submit_json), ["review", "id"])

      assert {:ok, [_respond_json]} =
               CLI.run_command(
                 %{
                   command: :review_plan_respond,
                   options: %{decision: "denied", feedback_notes: "Add tests first", json: true},
                   args: [Integer.to_string(review_id)]
                 },
                 tmp_dir
               )

      assert {:error, wait_json} =
               CLI.run_command(
                 %{
                   command: :review_plan_wait,
                   options: %{id: review_id, timeout: 1, json: true},
                   args: []
                 },
                 tmp_dir
               )

      wait_payload = decode_cli_json(wait_json)
      assert get_in(wait_payload, ["review", "status"]) == "denied"
      assert wait_payload["agent_feedback"] =~ "YOUR PLAN WAS NOT APPROVED"
      assert wait_payload["agent_feedback"] =~ "Add tests first"
    end

    test "wait timeout on pending review returns ok json payload", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      task = task_fixture(%{session: session})

      assert {:ok, review} =
               Mission.submit_review(%{
                 "task_id" => task.id,
                 "submission_body" => "Pending review"
               })

      assert {:ok, [wait_json]} =
               CLI.run_command(
                 %{
                   command: :review_plan_wait,
                   options: %{id: review.id, timeout: 0, json: true},
                   args: []
                 },
                 tmp_dir
               )

      wait_payload = decode_cli_json(wait_json)
      assert wait_payload["message"] == "timeout"
      assert wait_payload["timed_out"] == true
      assert wait_payload["status"] == "pending"
      assert get_in(wait_payload, ["review", "status"]) == "pending"
      assert wait_payload["browser_url"] =~ "/sessions/#{review.session_id}/reviews/#{review.id}"
    end
  end

  describe "review bridge server checks" do
    test "detects a serving review endpoint" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/reviews/123", fn conn ->
        Plug.Conn.resp(conn, 200, "ok")
      end)

      status = ReviewBridge.review_server_status("http://127.0.0.1:#{bypass.port}/reviews/123")
      assert status.serving == true
      assert status.status == 200
      assert status.error == nil
    end

    test "detects an unavailable review endpoint without hanging" do
      status =
        ReviewBridge.review_server_status("http://127.0.0.1:9/reviews/123",
          server_check_timeout_ms: 50
        )

      assert status.serving == false
      assert is_binary(status.error)
    end
  end

  describe "precommit commands" do
    test "precommit-check with no staged files", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join([tmp_dir, ".git"]))

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :precommit_check, options: %{project_root: tmp_dir}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "No policy violations"
    end

    test "precommit-install creates hook", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join([tmp_dir, ".git", "hooks"]))

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :precommit_install, options: %{project_root: tmp_dir}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Pre-commit hook installed"
      assert File.exists?(Path.join([tmp_dir, ".git", "hooks", "pre-commit"]))
    end

    test "precommit-uninstall when no hook exists", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join([tmp_dir, ".git", "hooks"]))

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :precommit_uninstall,
                       options: %{project_root: tmp_dir},
                       args: []
                     },
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "No pre-commit hook found"
    end

    test "precommit commands parse correctly" do
      assert {:ok, %{command: :precommit_check}} = CLI.parse(["precommit-check"])
      assert {:ok, %{command: :precommit_install}} = CLI.parse(["precommit-install"])
      assert {:ok, %{command: :precommit_uninstall}} = CLI.parse(["precommit-uninstall"])

      assert {:ok, parsed} =
               CLI.parse(["precommit-check", "--domain-pack", "hr", "--enforce"])

      assert parsed.command == :precommit_check
      assert parsed.options[:domain_pack] == "hr"
      assert parsed.options[:enforce] == true
    end

    test "precommit-install then uninstall lifecycle", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join([tmp_dir, ".git", "hooks"]))

      install_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :precommit_install, options: %{project_root: tmp_dir}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert install_output =~ "Pre-commit hook installed"

      uninstall_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :precommit_uninstall,
                       options: %{project_root: tmp_dir},
                       args: []
                     },
                     project_root: tmp_dir
                   )
        end)

      assert uninstall_output =~ "Pre-commit hook removed"
      refute File.exists?(Path.join([tmp_dir, ".git", "hooks", "pre-commit"]))
    end
  end

  describe "progress command" do
    test "progress with session id shows progress", %{tmp_dir: tmp_dir} do
      session = session_fixture(%{budget_cents: 5000, spent_cents: 1000})
      _task = task_fixture(%{session: session, status: "in_progress", title: "Live task"})

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :progress,
                       options: %{session_id: session.id},
                       args: []
                     },
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Session ##{session.id} Progress"
      assert output =~ "Tasks:"
      assert output =~ "Budget:"
      assert output =~ "Current task:"
      assert output =~ "Suggested next steps:"

      json_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :progress,
                       options: %{session_id: session.id, format: "json"},
                       args: []
                     },
                     project_root: tmp_dir
                   )
        end)

      assert {:ok, envelope} = Jason.decode(String.trim(json_output))
      payload = envelope["data"]
      assert payload["session_id"] == session.id
      assert get_in(payload, ["current_task", "title"]) == "Live task"
    end

    test "progress without session returns error" do
      error =
        capture_io(fn ->
          assert 1 ==
                   CLI.execute(
                     %{command: :progress, options: %{}, args: []},
                     project_root: "/nonexistent",
                     error_printer: &IO.puts/1
                   )
        end)

      assert error =~ "No active session"
    end

    test "progress parses correctly" do
      assert {:ok, %{command: :progress}} = CLI.parse(["progress"])

      assert {:ok, parsed} = CLI.parse(["progress", "--session-id", "42"])
      assert parsed.options[:session_id] == 42

      assert {:ok, parsed_json} = CLI.parse(["progress", "--format", "json"])
      assert parsed_json.options[:format] == "json"
    end
  end

  describe "findings translate command" do
    test "findings translate with no findings", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :findings_translate,
                       options: %{session_id: session.id},
                       args: []
                     },
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "No findings to translate"
    end

    test "findings translate with findings", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      _finding =
        finding_fixture(%{
          session: session,
          status: "open",
          title: "Hardcoded secret",
          severity: "critical",
          rule_id: "secret.hardcoded_api_key",
          category: "secret"
        })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :findings_translate,
                       options: %{session_id: session.id},
                       args: []
                     },
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Findings in plain English"
    end

    test "findings translate parses correctly" do
      assert {:ok, %{command: :findings_translate}} = CLI.parse(["findings", "translate"])

      assert {:ok, parsed} = CLI.parse(["findings", "translate", "--session-id", "10"])
      assert parsed.options[:session_id] == 10
    end
  end

  describe "outcome commands" do
    test "outcome record records an outcome" do
      session = session_fixture()

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :outcome_record,
                       options: %{},
                       args: [Integer.to_string(session.id), "deploy_success"]
                     },
                     project_root: "."
                   )
        end)

      assert output =~ "Recorded deploy_success for session ##{session.id}"
      assert output =~ "reward:"
    end

    test "outcome record rejects unknown outcome" do
      session = session_fixture()

      error =
        capture_io(fn ->
          assert 1 ==
                   CLI.execute(
                     %{
                       command: :outcome_record,
                       options: %{},
                       args: [Integer.to_string(session.id), "invalid_outcome"]
                     },
                     project_root: ".",
                     error_printer: &IO.puts/1
                   )
        end)

      assert error =~ "Unknown outcome"
    end

    test "outcome score for agent with no outcomes" do
      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :outcome_score,
                       options: %{},
                       args: ["unknown-agent"]
                     },
                     project_root: "."
                   )
        end)

      assert output =~ "Agent: unknown-agent"
    end

    test "outcome leaderboard with no outcomes" do
      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :outcome_leaderboard, options: %{}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "No outcomes recorded yet"
    end

    test "outcome leaderboard with recorded outcomes" do
      session = session_fixture()

      OutcomeTracker.record(session.id, :deploy_success)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :outcome_leaderboard, options: %{}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "Agent Leaderboard"
    end

    test "outcome commands parse correctly" do
      assert {:ok, parsed} = CLI.parse(["outcome", "record", "42", "deploy_success"])
      assert parsed.command == :outcome_record
      assert parsed.args == ["42", "deploy_success"]

      assert {:ok, parsed} = CLI.parse(["outcome", "score", "claude-code"])
      assert parsed.command == :outcome_score
      assert parsed.args == ["claude-code"]

      assert {:ok, parsed} = CLI.parse(["outcome", "leaderboard"])
      assert parsed.command == :outcome_leaderboard
    end
  end

  describe "web parity commands" do
    test "parse agents/task/router commands" do
      assert {:ok, %{command: :agents_list}} = CLI.parse(["agents", "list"])

      assert {:ok, %{command: :route_agent}} =
               CLI.parse(["route-agent", "--task", "build intake flow"])

      assert {:ok, %{command: :task_complete, args: ["42"]}} =
               CLI.parse(["task", "complete", "42"])

      assert {:ok, %{command: :task_claim, args: ["42"]}} = CLI.parse(["task", "claim", "42"])

      assert {:ok, %{command: :task_heartbeat, args: ["42"]}} =
               CLI.parse(["task", "heartbeat", "42", "--progress", "50"])

      assert {:ok, %{command: :task_checks, args: ["42"]}} =
               CLI.parse(["task", "checks", "42", "--checks", "[]"])

      assert {:ok, %{command: :task_report, args: ["42"]}} =
               CLI.parse(["task", "report", "42", "--status", "done"])
    end

    test "agents list supports json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      assert {:ok, [payload]} =
               CLI.run_command(
                 %{command: :agents_list, options: %{json: true}, args: []},
                 tmp_dir
               )

      decoded = decode_cli_json(payload)
      assert is_list(decoded["agents"])
      assert Enum.any?(decoded["agents"], &(&1["id"] == "opencode"))
    end

    test "route-agent returns recommendation and json", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      assert {:ok, [payload]} =
               CLI.run_command(
                 %{
                   command: :route_agent,
                   options: %{task: "build secure review endpoint", risk_tier: "high", json: true},
                   args: []
                 },
                 tmp_dir
               )

      decoded = decode_cli_json(payload)
      recommendation = decoded["recommendation"]
      assert is_binary(recommendation["agent"])
      assert is_list(recommendation["rationale"])
    end

    test "task lifecycle commands complete claim heartbeat checks and report", %{tmp_dir: tmp_dir} do
      session = session_fixture(risk_tier: "low")
      task = task_fixture(%{session: session, status: "queued"})
      write_binding(tmp_dir, session)

      assert {:ok, claim_lines} =
               CLI.run_command(
                 %{
                   command: :task_claim,
                   options: %{execution_mode: "agent"},
                   args: [Integer.to_string(task.id)]
                 },
                 tmp_dir
               )

      assert Enum.any?(claim_lines, &String.contains?(&1, "Claimed task"))

      assert {:ok, heartbeat_lines} =
               CLI.run_command(
                 %{
                   command: :task_heartbeat,
                   options: %{progress: 40, note: "halfway"},
                   args: [Integer.to_string(task.id)]
                 },
                 tmp_dir
               )

      assert Enum.any?(heartbeat_lines, &String.contains?(&1, "Heartbeat recorded"))

      checks = ~s([{"check_type":"ci","status":"passed","summary":"ok"}])

      assert {:ok, checks_lines} =
               CLI.run_command(
                 %{
                   command: :task_checks,
                   options: %{checks: checks},
                   args: [Integer.to_string(task.id)]
                 },
                 tmp_dir
               )

      assert Enum.any?(checks_lines, &String.contains?(&1, "Recorded 1 check result"))

      assert {:ok, report_lines} =
               CLI.run_command(
                 %{
                   command: :task_report,
                   options: %{status: "done", output: "{}", metadata: "{}"},
                   args: [Integer.to_string(task.id)]
                 },
                 tmp_dir
               )

      assert Enum.any?(report_lines, &String.contains?(&1, "Reported task"))

      assert {:ok, complete_lines} =
               CLI.run_command(
                 %{command: :task_complete, options: %{}, args: [Integer.to_string(task.id)]},
                 tmp_dir
               )

      assert Enum.any?(complete_lines, &String.contains?(&1, "Completed task"))
    end
  end

  describe "observability commands" do
    test "obs commands parse correctly" do
      assert {:ok, %{command: :obs_status}} = CLI.parse(["obs"])
      assert {:ok, %{command: :obs_status}} = CLI.parse(["obs", "status"])
      assert {:ok, %{command: :obs_loop_status}} = CLI.parse(["obs", "loop"])
      assert {:ok, %{command: :obs_loop_status}} = CLI.parse(["obs", "loop-status"])
      assert {:ok, %{command: :obs_costs}} = CLI.parse(["obs", "costs"])
      assert {:ok, %{command: :obs_recommend}} = CLI.parse(["obs", "recommend"])
      assert {:ok, %{command: :obs_evals}} = CLI.parse(["obs", "evals"])
      assert {:ok, %{command: :obs_regressions}} = CLI.parse(["obs", "regressions"])

      assert {:ok, %{command: :obs_benchmark_approve, args: [123]}} =
               CLI.parse(["obs", "benchmarks", "approve", "123"])

      assert {:ok, %{command: :obs_benchmark_reject, args: [123]}} =
               CLI.parse(["obs", "benchmarks", "reject", "123"])

      assert {:ok, %{command: :obs_benchmark_archive, args: [123]}} =
               CLI.parse(["obs", "benchmarks", "archive", "123"])

      assert {:ok, %{command: :obs_compare}} = CLI.parse(["obs", "compare"])
      assert {:ok, %{command: :obs_timeline}} = CLI.parse(["obs", "timeline"])
      assert {:ok, %{command: :obs_timeline, args: [123]}} = CLI.parse(["obs", "timeline", "123"])
      assert {:ok, %{command: :obs_memory}} = CLI.parse(["obs", "memory"])
      assert {:ok, %{command: :obs_memory, args: [123]}} = CLI.parse(["obs", "memory", "123"])
      assert {:ok, %{command: :obs_run, args: [123]}} = CLI.parse(["obs", "run", "123"])
      assert {:ok, %{command: :obs_export, args: [123]}} = CLI.parse(["obs", "export", "123"])

      assert {:ok, %{command: :obs_import, args: ["trace.json"]}} =
               CLI.parse(["obs", "import", "trace.json", "--dry-run"])

      assert {:ok, %{command: :obs_import, args: ["trace.json"], options: [persist: true]}} =
               CLI.parse(["obs", "import", "trace.json", "--persist"])

      assert {:error, _} = CLI.parse(["obs", "run", "not-an-id"])
    end

    test "obs status renders compact run observability", %{tmp_dir: tmp_dir} do
      session =
        session_fixture(%{budget_cents: 2_000, daily_budget_cents: 2_000, spent_cents: 300})

      finding_fixture(%{
        session: session,
        title: "Review needed",
        severity: "medium",
        status: "open"
      })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_status, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability:"
      assert output =~ "Health:"
      assert output =~ "Budget:"
      assert output =~ "Findings:"
      assert output =~ "Recommendations:"
    end

    test "obs loop renders canonical human-gated learning status", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "Loop CLI finding",
        severity: "high",
        status: "open",
        category: "security",
        rule_id: "security.loop_cli"
      })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_loop_status, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability learning loop:"
      assert output =~ "Automatic promotion: false"
      assert output =~ "Problems:"
      assert output =~ "Benchmarks:"
    end

    test "obs problems parses and renders grouped problems", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "SQL problem",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.sql_injection"
      })

      write_binding(tmp_dir, session)

      assert {:ok, %{command: :obs_problems}} = CLI.parse(["obs", "problems"])

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_problems, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability problems:"
      assert output =~ "security.sql_injection"
      assert output =~ "Health: red"
      assert output =~ "Feedback loop: Regression eval for security.sql_injection"
      assert output =~ "Human gate required: true"
    end

    test "obs costs renders grouped local cost summary", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      assert {:ok, _invocation} =
               %Invocation{}
               |> Invocation.changeset(%{
                 session_id: session.id,
                 source: "codex-cli",
                 tool: "ck_validate",
                 provider: "openai",
                 model: "gpt-5.5",
                 input_tokens: 900,
                 cached_input_tokens: 100,
                 output_tokens: 250,
                 estimated_cost_cents: 11,
                 decision: "allow",
                 metadata: %{}
               })
               |> Repo.insert()

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_costs, options: %{by: "tool"}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability costs:"
      assert output =~ "Grouped by: tool"
      assert output =~ "ck_validate"
      assert output =~ "Recommendations:"
    end

    test "obs costs supports json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      assert {:ok, _invocation} =
               %Invocation{}
               |> Invocation.changeset(%{
                 session_id: session.id,
                 source: "opencode",
                 tool: "ck_budget",
                 provider: "anthropic",
                 model: "claude-sonnet",
                 input_tokens: 400,
                 output_tokens: 120,
                 estimated_cost_cents: 7,
                 decision: "allow",
                 metadata: %{}
               })
               |> Repo.insert()

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_costs, options: %{by: "provider", json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "by" => "provider",
               "totals" => %{"invocations" => 1, "estimated_cost_cents" => 7},
               "groups" => [%{"name" => "anthropic"}]
             } = decode_cli_json(output)
    end

    test "obs imports renders persisted snapshots", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      export_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_export, options: %{json: true}, args: [session.id]},
                     project_root: "."
                   )
        end)

      path = Path.join(tmp_dir, "observability-export.json")
      File.write!(path, export_output)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{command: :obs_import, options: %{persist: true}, args: [path]},
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_imports, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability imports: 1 persisted snapshot"
      assert output =~ "Integrity: verified: 1"
      assert output =~ "Recent imports:"
      assert output =~ "hash"
    end

    test "obs imports supports json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      export_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_export, options: %{json: true}, args: [session.id]},
                     project_root: "."
                   )
        end)

      path = Path.join(tmp_dir, "observability-export-json.json")
      File.write!(path, export_output)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{command: :obs_import, options: %{persist: true}, args: [path]},
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_imports, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "count" => 1,
               "by_integrity" => %{"verified" => 1},
               "recent" => [%{"original_session_id" => original_session_id, "mutation" => "none"}]
             } = decode_cli_json(output)

      assert original_session_id == session.id
    end

    test "obs trends renders local trend summary", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "Trend CLI finding",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.trend_cli"
      })

      assert {:ok, _invocation} =
               %Invocation{}
               |> Invocation.changeset(%{
                 session_id: session.id,
                 source: "opencode",
                 tool: "ck_validate",
                 provider: "openai",
                 model: "gpt-5.5",
                 estimated_cost_cents: 5,
                 decision: "allow",
                 metadata: %{}
               })
               |> Repo.insert()

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_trends, options: %{days: 7}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability trends:"
      assert output =~ "Runs: 1 total"
      assert output =~ "Findings: 1 active / 1 blocked"
      assert output =~ "Daily series:"
    end

    test "obs trends supports json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_trends, options: %{days: 3, json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "days" => 3,
               "totals" => %{"runs" => 1},
               "series" => series
             } = decode_cli_json(output)

      assert length(series) == 3
    end

    test "obs recommend renders prioritized recommendations", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "Recommendation issue",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.recommend"
      })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_recommend, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability recommendations:"
      assert output =~ "Health: red"
      assert output =~ "Regression eval for security.recommend"
      assert output =~ "Human gate required:"
    end

    test "obs recommend supports json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "JSON recommendation issue",
        severity: "high",
        status: "open",
        category: "review",
        rule_id: "review.recommend"
      })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_recommend, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{"count" => count, "actions" => actions} = decode_cli_json(output)
      assert count >= 1
      assert Enum.any?(actions, &(&1["title"] == "Regression eval for review.recommend"))
    end

    test "obs promotions reports advisory candidates as json", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI promotion finding",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.cli_promotion"
      })

      write_binding(tmp_dir, session)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_evals_save, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_promotions, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "promotion_execution" => false,
               "candidates" => [
                 %{"readiness" => "needs_draft", "rule_id" => "security.cli_promotion"}
               ]
             } = decode_cli_json(output)
    end

    test "obs benchmarks history reports readiness as json", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI history finding",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.cli_history"
      })

      write_binding(tmp_dir, session)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_evals_save, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_draft, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      draft_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_drafts, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      %{"drafts" => [%{"id" => draft_id}]} = decode_cli_json(draft_output)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_approve, options: %{}, args: [draft_id]},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_materialize, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_history, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "coverage" => %{"materialized_scenarios" => 1, "benchmark_runs" => 0},
               "readiness" => %{"status" => "yellow"}
             } = decode_cli_json(output)
    end

    test "obs benchmarks run dry-run previews without creating runs", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI dry run finding",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.cli_dry_run"
      })

      write_binding(tmp_dir, session)
      run_count = Repo.aggregate(Run, :count, :id)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_evals_save, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_draft, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      draft_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_drafts, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      %{"drafts" => [%{"id" => draft_id}]} = decode_cli_json(draft_output)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_approve, options: %{}, args: [draft_id]},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_materialize, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :obs_benchmark_run,
                       options: %{dry_run: true, subjects: "controlkeel_validate"},
                       args: []
                     },
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability benchmark run preview:"
      assert output =~ "Benchmark execution: false"
      assert output =~ "--execute"
      assert Repo.aggregate(Run, :count, :id) == run_count
    end

    test "obs benchmarks run refuses execution without execute flag", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      output =
        capture_io(:stderr, fn ->
          assert 1 ==
                   CLI.execute(
                     %{
                       command: :obs_benchmark_run,
                       options: %{dry_run: false, subjects: "controlkeel_validate"},
                       args: []
                     },
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Refusing to run without --execute"
    end

    test "obs benchmarks materialize creates local scenarios", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI materialize finding",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.cli_materialize"
      })

      write_binding(tmp_dir, session)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_evals_save, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_draft, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      draft_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_drafts, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      %{"drafts" => [%{"id" => draft_id}]} = decode_cli_json(draft_output)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_approve, options: %{}, args: [draft_id]},
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_materialize, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability benchmark scenarios materialized:"
      assert output =~ "Materialized: 1"
      assert output =~ "Benchmark execution: false"
    end

    test "obs benchmarks scenarios lists generated scenarios as json", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI scenario list finding",
        severity: "high",
        status: "open",
        category: "review",
        rule_id: "review.cli_scenario"
      })

      write_binding(tmp_dir, session)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_evals_save, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_draft, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      draft_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_drafts, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      %{"drafts" => [%{"id" => draft_id}]} = decode_cli_json(draft_output)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_approve, options: %{}, args: [draft_id]},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_materialize, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_scenarios, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "count" => 1,
               "scenarios" => [%{"expected_rules" => ["review.cli_scenario"]}]
             } = decode_cli_json(output)
    end

    test "obs benchmarks draft generates local drafts", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI benchmark draft finding",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.cli_benchmark_draft"
      })

      write_binding(tmp_dir, session)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{command: :obs_evals_save, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_draft, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability benchmark drafts generated:"
      assert output =~ "Stored: 1"
      assert output =~ "Human gate required: true"
      assert output =~ "draft_record_only"
    end

    test "obs benchmarks drafts lists local drafts as json", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI benchmark draft listing",
        severity: "high",
        status: "open",
        category: "review",
        rule_id: "review.cli_benchmark_draft"
      })

      write_binding(tmp_dir, session)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_evals_save, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_draft, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_drafts, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "count" => 1,
               "by_status" => %{"draft" => 1},
               "drafts" => [%{"status" => "draft", "human_gate_required" => true}]
             } = decode_cli_json(output)
    end

    test "obs benchmarks approve updates a local draft status", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI benchmark draft approval",
        severity: "high",
        status: "open",
        category: "review",
        rule_id: "review.cli_benchmark_approval"
      })

      write_binding(tmp_dir, session)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_evals_save, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_draft, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      draft = Repo.one!(ControlKeel.Observability.BenchmarkDraft)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_approve, options: %{}, args: [draft.id]},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability benchmark draft updated:"
      assert output =~ "Status: approved"
      assert output =~ "draft_status_only"
    end

    test "obs regressions reports benchmark posture", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_regressions, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability regressions:"
      assert output =~ "Benchmark runs:"
      assert output =~ "Average catch rate:"
      assert output =~ "Recent runs:"
    end

    test "obs regressions supports json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI regressions finding",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.cli_regressions"
      })

      write_binding(tmp_dir, session)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_evals_save, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_draft, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      draft_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_benchmark_drafts, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      %{"drafts" => [%{"id" => draft_id}]} = decode_cli_json(draft_output)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_approve, options: %{}, args: [draft_id]},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :obs_benchmark_materialize, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{
                     command: :obs_benchmark_run,
                     options: %{subjects: "controlkeel_validate", execute: true},
                     args: []
                   },
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_regressions, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "benchmark_runs" => %{"count" => count, "recent" => [_ | _]},
               "health" => %{"status" => _}
             } = decode_cli_json(output)

      assert count >= 1
    end

    test "obs evals save persists advisory candidates", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI save eval finding",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.cli_save_eval"
      })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_evals_save, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability eval candidates saved:"
      assert output =~ "Stored: 1"
      assert output =~ "Human gate required: true"
    end

    test "obs evals persisted lists saved candidates as json", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "CLI saved eval listing",
        severity: "high",
        status: "open",
        category: "review",
        rule_id: "review.cli_saved_eval"
      })

      write_binding(tmp_dir, session)

      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{command: :obs_evals_save, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_evals_persisted, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "count" => 1,
               "by_status" => %{"open" => 1},
               "candidates" => [
                 %{"rule_id" => "review.cli_saved_eval", "human_gate_required" => true}
               ]
             } = decode_cli_json(output)
    end

    test "obs evals renders advisory eval candidates", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "Eval CLI issue",
        severity: "critical",
        status: "blocked",
        category: "security",
        rule_id: "security.eval_cli"
      })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_evals, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability eval candidates:"
      assert output =~ "Regression eval for security.eval_cli"
      assert output =~ "Benchmark hint: security-regression"
      assert output =~ "Human gate required: true"
    end

    test "obs evals supports json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "Eval JSON issue",
        severity: "high",
        status: "open",
        category: "review",
        rule_id: "review.eval_json"
      })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_evals, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{"count" => 1, "candidates" => [%{"rule_id" => "review.eval_json"}]} =
               decode_cli_json(output)
    end

    test "obs compare renders invocation comparison", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      assert {:ok, _invocation} =
               %Invocation{}
               |> Invocation.changeset(%{
                 session_id: session.id,
                 source: "codex-cli",
                 tool: "ck_validate",
                 provider: "openai",
                 model: "gpt-5.5",
                 input_tokens: 700,
                 output_tokens: 200,
                 estimated_cost_cents: 9,
                 decision: "allow",
                 metadata: %{}
               })
               |> Repo.insert()

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_compare, options: %{by: "source"}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability comparison by source:"
      assert output =~ "codex-cli"
      assert output =~ "cent(s)/call"
      assert output =~ "Recommendations:"
    end

    test "obs compare supports json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      assert {:ok, _invocation} =
               %Invocation{}
               |> Invocation.changeset(%{
                 session_id: session.id,
                 source: "opencode",
                 tool: "ck_budget",
                 provider: "anthropic",
                 model: "claude-sonnet",
                 input_tokens: 300,
                 output_tokens: 100,
                 estimated_cost_cents: 4,
                 decision: "warn",
                 metadata: %{}
               })
               |> Repo.insert()

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_compare, options: %{by: "model", json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "by" => "model",
               "groups" => [%{"name" => "claude-sonnet", "decisions" => %{"warn" => 1}}]
             } = decode_cli_json(output)
    end

    test "obs timeline renders current session events", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      assert {:ok, _event} =
               %SessionEvent{}
               |> SessionEvent.changeset(%{
                 session_id: session.id,
                 event_type: "context_loaded",
                 actor: "agent",
                 summary: "Loaded context",
                 payload: %{},
                 metadata: %{}
               })
               |> Repo.insert()

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_timeline, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability timeline:"
      assert output =~ "context_loaded"
      assert output =~ "Loaded context"
    end

    test "obs timeline supports explicit session id and json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      assert {:ok, _event} =
               %SessionEvent{}
               |> SessionEvent.changeset(%{
                 session_id: session.id,
                 event_type: "review_submitted",
                 actor: "agent",
                 summary: "Submitted review",
                 payload: %{},
                 metadata: %{}
               })
               |> Repo.insert()

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_timeline, options: %{json: true}, args: [session.id]},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "session" => %{"id" => id},
               "events" => [%{"event_type" => "review_submitted"} | _]
             } = decode_cli_json(output)

      assert id == session.id
    end

    test "obs memory-quality renders workspace memory diagnostics", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      memory_record_fixture(%{
        session: session,
        title: "CLI stale memory",
        summary: "Review stale memory.",
        source_type: "agent"
      })

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_memory_quality, options: %{stale_days: 1}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability memory quality:"
      assert output =~ "Active:"
      assert output =~ "Stale candidates:"
      assert output =~ "Recommendations:"
    end

    test "obs memory-quality supports json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      memory_record_fixture(%{
        session: session,
        title: "JSON quality memory",
        summary: "Quality summary.",
        source_type: "agent"
      })

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :obs_memory_quality,
                       options: %{stale_days: 7, json: true},
                       args: []
                     },
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "stale_days" => 7,
               "totals" => %{"records" => records},
               "distributions" => %{"by_source" => %{"agent" => agent_records}}
             } = decode_cli_json(output)

      assert records >= 1
      assert agent_records >= 1
    end

    test "obs memory renders current session memory summary", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      memory_record_fixture(%{
        session: session,
        record_type: "decision",
        title: "CLI memory",
        summary: "CLI memory summary.",
        source_type: "agent"
      })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_memory, options: %{}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability memory:"
      assert output =~ "CLI memory"
      assert output =~ "Memory:"
    end

    test "obs memory supports explicit session id and json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      memory_record_fixture(%{
        session: session,
        record_type: "checkpoint",
        title: "JSON memory",
        summary: "JSON memory summary.",
        source_type: "review"
      })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_memory, options: %{json: true}, args: [session.id]},
                     project_root: tmp_dir
                   )
        end)

      assert %{
               "session" => %{"id" => id},
               "memory" => %{"active" => active, "recent" => recent}
             } = decode_cli_json(output)

      assert id == session.id
      assert active >= 1
      assert Enum.any?(recent, &(&1["title"] == "JSON memory"))
    end

    test "obs problems supports json output", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      finding_fixture(%{
        session: session,
        title: "Review problem",
        severity: "medium",
        status: "open",
        category: "review",
        rule_id: "review.required"
      })

      write_binding(tmp_dir, session)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_problems, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert %{"count" => 1, "problems" => [%{"rule_id" => "review.required"}]} =
               decode_cli_json(output)
    end

    test "obs run supports json output", %{tmp_dir: _tmp_dir} do
      session =
        session_fixture(%{budget_cents: 2_000, daily_budget_cents: 2_000, spent_cents: 300})

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_run, options: %{json: true}, args: [session.id]},
                     project_root: "."
                   )
        end)

      assert %{"session" => %{"id" => id}, "health" => %{"status" => _}} = decode_cli_json(output)
      assert id == session.id
    end

    test "obs export supports json telemetry envelopes", %{tmp_dir: _tmp_dir} do
      session = session_fixture()

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_export, options: %{json: true}, args: [session.id]},
                     project_root: "."
                   )
        end)

      assert %{
               "schema_version" => "controlkeel.observability.v1",
               "session_run" => %{"session" => %{"id" => id}},
               "redaction" => %{"policy" => "summary_only"},
               "integrity" => %{
                 "import_mutation_allowed" => false,
                 "payload_sha256" => payload_sha256
               }
             } = decode_cli_json(output)

      assert id == session.id
      assert payload_sha256 =~ ~r/^[a-f0-9]{64}$/
    end

    test "obs import dry-run previews telemetry envelopes without mutation", %{tmp_dir: tmp_dir} do
      session = session_fixture()

      export_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_export, options: %{json: true}, args: [session.id]},
                     project_root: "."
                   )
        end)

      path = Path.join(tmp_dir, "observability-export.json")
      File.write!(path, export_output)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_import, options: %{dry_run: true}, args: [path]},
                     project_root: "."
                   )
        end)

      assert output =~ "Observability import dry-run:"
      assert output =~ "Session:"
      assert output =~ "Integrity: verified"
      assert output =~ "Mutation: none"
    end

    test "obs import persist stores a local telemetry snapshot", %{tmp_dir: tmp_dir} do
      session = session_fixture()
      write_binding(tmp_dir, session)

      export_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_export, options: %{json: true}, args: [session.id]},
                     project_root: "."
                   )
        end)

      path = Path.join(tmp_dir, "observability-export.json")
      File.write!(path, export_output)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :obs_import, options: %{persist: true}, args: [path]},
                     project_root: tmp_dir
                   )
        end)

      assert output =~ "Observability import persisted:"
      assert output =~ "Status: stored"
      assert output =~ "Integrity: verified"
      assert output =~ "Mutation: none"
      assert Repo.aggregate(ImportedEnvelope, :count, :id) == 1

      persisted = Repo.one(ImportedEnvelope)
      assert persisted.workspace_id == session.workspace_id
      assert persisted.session_id == session.id
    end

    test "obs import requires dry-run", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "observability-export.json")
      File.write!(path, Jason.encode!(%{}))

      output =
        capture_io(:stderr, fn ->
          assert 1 ==
                   CLI.execute(
                     %{command: :obs_import, options: %{}, args: [path]},
                     project_root: "."
                   )
        end)

      assert output =~ "requires --dry-run or --persist"
    end
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
end
