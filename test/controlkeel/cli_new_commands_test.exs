defmodule ControlKeel.CLI.NewCommandsTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures
  import ExUnit.CaptureIO

  alias ControlKeel.CLI
  alias ControlKeel.Mission
  alias ControlKeel.ProjectBinding
  alias ControlKeel.Governance.CircuitBreaker
  alias ControlKeel.Governance.AgentMonitor
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

      assert Enum.any?(open_lines, &String.contains?(&1, "/reviews/#{review.id}"))
      assert Enum.any?(open_lines, &String.contains?(&1, "Opened browser: false"))

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

      payload = Jason.decode!(submit_json)
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

      payload = Jason.decode!(submit_json)
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

      payload = Jason.decode!(submit_json)
      review_id = get_in(payload, ["review", "id"])

      assert is_integer(review_id)
      assert get_in(payload, ["review", "task_id"]) == task.id
      assert payload["browser_url"] =~ "/reviews/#{review_id}"

      assert {:ok, [open_json]} =
               CLI.run_command(
                 %{command: :review_plan_open, options: %{id: review_id, json: true}, args: []},
                 tmp_dir
               )

      open_payload = Jason.decode!(open_json)
      assert open_payload["browser_url"] =~ "/reviews/#{review_id}"
      assert open_payload["open_target"] == "manual"
      assert open_payload["opened"] == false
      assert open_payload["remote"] == true

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

      wait_payload = Jason.decode!(wait_json)
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

      review_id = get_in(Jason.decode!(submit_json), ["review", "id"])

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

      wait_payload = Jason.decode!(wait_json)
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

      wait_payload = Jason.decode!(wait_json)
      assert wait_payload["message"] == "timeout"
      assert wait_payload["timed_out"] == true
      assert wait_payload["status"] == "pending"
      assert get_in(wait_payload, ["review", "status"]) == "pending"
      assert wait_payload["browser_url"] =~ "/reviews/#{review.id}"
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

      assert {:ok, payload} = Jason.decode(String.trim(json_output))
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

  describe "circuit-breaker commands" do
    test "circuit-breaker status shows empty when no agents" do
      start_supervised!({CircuitBreaker, []})

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :circuit_breaker_status, options: %{}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "No agents tracked"
    end

    test "circuit-breaker trip and reset cycle" do
      start_supervised!({CircuitBreaker, []})

      trip_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :circuit_breaker_trip,
                       options: %{agent_id: "test-agent"},
                       args: []
                     },
                     project_root: "."
                   )
        end)

      assert trip_output =~ "Circuit breaker tripped for agent: test-agent"

      status_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :circuit_breaker_status,
                       options: %{agent_id: "test-agent"},
                       args: []
                     },
                     project_root: "."
                   )
        end)

      assert status_output =~ "Agent: test-agent"
      assert status_output =~ "Status: tripped"

      reset_output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{
                       command: :circuit_breaker_reset,
                       options: %{agent_id: "test-agent"},
                       args: []
                     },
                     project_root: "."
                   )
        end)

      assert reset_output =~ "Circuit breaker reset for agent: test-agent"
    end

    test "circuit-breaker all statuses" do
      start_supervised!({CircuitBreaker, []})

      :ok = CircuitBreaker.record_event("agent-a", :api_call)
      :ok = CircuitBreaker.record_event("agent-b", :file_modification)

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :circuit_breaker_status, options: %{}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "Circuit Breaker Status"
    end

    test "circuit-breaker commands parse correctly" do
      assert {:ok, %{command: :circuit_breaker_status}} =
               CLI.parse(["circuit-breaker", "status"])

      assert {:ok, parsed} = CLI.parse(["circuit-breaker", "status", "--agent-id", "my-agent"])
      assert parsed.options[:agent_id] == "my-agent"

      assert {:ok, parsed} = CLI.parse(["circuit-breaker", "trip", "my-agent"])
      assert parsed.command == :circuit_breaker_trip
      assert parsed.options[:agent_id] == "my-agent"

      assert {:ok, parsed} = CLI.parse(["circuit-breaker", "reset", "my-agent"])
      assert parsed.command == :circuit_breaker_reset
      assert parsed.options[:agent_id] == "my-agent"
    end
  end

  describe "agents monitor command" do
    test "agents monitor with no active agents" do
      start_supervised!({AgentMonitor, []})

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :agents_monitor, options: %{}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "No active agents"
    end

    test "agents monitor with specific agent with no events" do
      start_supervised!({AgentMonitor, []})

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :agents_monitor, options: %{agent_id: "ghost"}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "No events for agent: ghost"
    end

    test "agents monitor shows active agents" do
      start_supervised!({AgentMonitor, []})

      :ok = AgentMonitor.track("agent-x", :api_call, metadata: %{path: "/test"})

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :agents_monitor, options: %{}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "Active agents"
      assert output =~ "agent-x"
    end

    test "agents monitor shows events for specific agent" do
      start_supervised!({AgentMonitor, []})

      :ok = AgentMonitor.track("agent-y", :file_write, metadata: %{path: "lib/app.ex"})

      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(
                     %{command: :agents_monitor, options: %{agent_id: "agent-y"}, args: []},
                     project_root: "."
                   )
        end)

      assert output =~ "Recent events for agent-y"
    end

    test "agents monitor parses correctly" do
      assert {:ok, %{command: :agents_monitor}} = CLI.parse(["agents", "monitor"])

      assert {:ok, parsed} = CLI.parse(["agents", "monitor", "--agent-id", "cursor"])
      assert parsed.options[:agent_id] == "cursor"
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

      decoded = Jason.decode!(payload)
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

      decoded = Jason.decode!(payload)
      recommendation = decoded["recommendation"]
      assert is_binary(recommendation["agent"])
      assert is_list(recommendation["rationale"])
    end

    test "task lifecycle commands complete claim heartbeat checks and report", %{tmp_dir: tmp_dir} do
      session = session_fixture()
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
end
