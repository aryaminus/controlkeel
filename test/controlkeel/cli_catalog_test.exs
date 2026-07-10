defmodule ControlKeel.CLI.CatalogTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Agent.Integration
  alias ControlKeel.CLI
  alias ControlKeel.CLI.Catalog

  @representative_commands [
    ["setup"],
    ["doctor", "--json"],
    ["capabilities", "--json"],
    ["attach", "codex-cli", "--scope", "project"],
    ["attach", "doctor"],
    ["context", "--json"],
    ["validate", "--content", "hello", "--kind", "text"],
    ["review", "plan", "submit", "--stdin"],
    ["review", "diff", "--base", "main", "--head", "HEAD"],
    ["route-agent", "--task", "fix bug", "--json"],
    ["run", "task", "123", "--agent", "auto"],
    ["obs", "status", "--json"],
    ["obs", "benchmarks", "run", "--dry-run"],
    ["memory", "search", "routing"],
    ["mcp", "registry", "list"],
    ["skills", "list", "--json"],
    ["tool", "groups", "suggest", "--format", "json"],
    ["cloud", "doctor"],
    ["provider", "doctor"],
    ["sandbox", "status"],
    ["benchmark", "list"],
    ["eval", "run"],
    ["deploy", "analyze"],
    ["runtime", "export", "devin"],
    ["outcome", "leaderboard"]
  ]

  @core_families [
    :core,
    :attach_hosts,
    :governance,
    :review,
    :execution,
    :observability,
    :memory_continuity,
    :mcp_tools,
    :skills_plugins_hooks,
    :cloud_selfhost,
    :providers_budget,
    :sandbox_security_code_mode,
    :benchmarks_harness,
    :deployment_portability,
    :learning_loop
  ]

  test "representative parsed commands resolve to catalog entries" do
    for argv <- @representative_commands do
      assert {:ok, parsed} = CLI.parse(argv)

      assert entry = Catalog.for_command(parsed.command),
             "missing catalog entry for #{inspect(parsed.command)} parsed from #{inspect(argv)}"

      assert is_binary(entry.path) and entry.path != ""
      assert is_binary(entry.summary) and entry.summary != ""
      assert entry.examples != []
    end
  end

  test "supported attach hosts share the attach catalog entry" do
    for agent <- Integration.attachable_ids() do
      scope = Integration.get(agent).supported_scopes |> List.first()
      assert {:ok, %{command: :attach}} = CLI.parse(["attach", agent, "--scope", scope])
    end

    entry = Catalog.for_command(:attach)
    assert entry.family == :attach_hosts
    assert "ck_attach" in entry.related_mcp_tools
    assert "agent-integration" in entry.related_skills
    assert entry.safety.repo_write
  end

  test "every catalog entry has required metadata and safety keys" do
    required = Catalog.required_metadata_keys()
    safety_keys = Catalog.safety_keys()

    for entry <- Catalog.all() do
      for key <- required do
        assert Map.has_key?(entry, key), "#{inspect(entry.command)} missing #{key}"
      end

      assert is_atom(entry.command)
      assert is_binary(entry.path) and entry.path != ""
      assert is_atom(entry.family)
      assert is_binary(entry.summary) and entry.summary != ""
      assert is_list(entry.examples) and entry.examples != []
      assert Enum.all?(entry.examples, &String.starts_with?(&1, "controlkeel "))
      assert is_list(entry.inputs) and entry.inputs != []
      assert is_list(entry.outputs) and entry.outputs != []
      assert is_binary(entry.help_topic) and entry.help_topic != ""

      for key <- safety_keys do
        assert Map.has_key?(entry.safety, key), "#{inspect(entry.command)} safety missing #{key}"

        assert is_boolean(entry.safety[key]),
               "#{inspect(entry.command)} safety #{key} must be boolean"
      end
    end
  end

  test "each command has exactly one catalog and dispatch owner" do
    entries = Catalog.all()
    command_counts = Enum.frequencies_by(entries, & &1.command)

    assert Enum.all?(command_counts, fn {_command, count} -> count == 1 end)

    assert MapSet.new(Map.keys(CLI.dispatch_modules())) ==
             MapSet.new(Catalog.families() |> Map.keys())

    for module <- Map.values(CLI.dispatch_modules()) do
      assert Code.ensure_loaded?(module)
      assert function_exported?(module, :run_command, 2)
    end
  end

  test "catalog covers the core product families" do
    families = Catalog.families()

    for family <- @core_families do
      assert Map.has_key?(families, family), "missing family #{inspect(family)}"
      assert families[family] != []
    end
  end

  test "core workflows cross-link CLI to MCP, skills, hooks, plugins, and portability" do
    governance = Catalog.for_command(:validate)
    review = Catalog.for_command(:review_plan_submit)
    skills = Catalog.for_command(:skills_install)
    mcp = Catalog.for_command(:mcp)
    deploy = Catalog.for_command(:deploy_analyze)

    assert "ck_validate" in governance.related_mcp_tools
    assert "controlkeel-governance" in governance.related_skills

    assert "ck_review_submit" in review.related_mcp_tools
    assert "plan-slice" in review.related_skills

    assert "ck_skill_list" in skills.related_mcp_tools
    assert "PreToolUse" in skills.related_hooks
    assert "codex" in skills.related_plugins

    assert "ck_mcp_discover" in mcp.related_mcp_tools
    assert "ck_deployment_advisor" in deploy.related_mcp_tools
  end

  test "scoped command help renders catalog metadata for command prefixes" do
    scoped = [
      {["review", "plan", "submit", "--help"], "Command: controlkeel review plan submit",
       "ck_review_submit"},
      {["attach", "--help"], "Command: controlkeel attach <agent>", "agent-integration"},
      {["obs", "benchmarks", "run", "--help"], "Command: controlkeel obs benchmarks run",
       "benchmark-operator"},
      {["cloud", "connect", "--help"], "Command: controlkeel cloud connect", "cloud"}
    ]

    for {argv, command_line, expected_detail} <- scoped do
      assert {:ok, %{command: :help, args: args}} = CLI.parse(argv)
      output = ControlKeel.CLI.Help.render(args)

      assert output =~ "ControlKeel command help"
      assert output =~ command_line
      assert output =~ "Examples:"
      assert output =~ "Inputs:"
      assert output =~ "Outputs:"
      assert output =~ "Safety:"
      assert output =~ expected_detail
    end
  end

  test "catalog-backed parse errors are scoped and actionable" do
    assert {:error, message} = CLI.parse(["review", "plan", "submit", "--not-a-real-flag"])

    assert message =~ "Unknown option(s): --not-a-real-flag"
    assert message =~ "for controlkeel review plan submit"
    assert message =~ "Use:"
    assert message =~ "controlkeel review plan submit --stdin --json"
    assert message =~ "Help:"
    assert message =~ "controlkeel review plan submit --help"
    refute message =~ "ControlKeel CLI\n"
  end

  test "json parse errors use stable catalog-backed envelope" do
    assert {:error, message} =
             CLI.parse(["review", "plan", "submit", "--not-a-real-flag", "--json"])

    assert %{
             "error" => error,
             "code" => "invalid_option",
             "command" => "review plan submit",
             "hint" => "Run: controlkeel review plan submit --help",
             "examples" => examples,
             "help_topic" => "review",
             "details" => %{"invalid_options" => ["--not-a-real-flag"]}
           } = decode_cli_json(message)

    assert error =~ "Unknown option(s): --not-a-real-flag"
    assert "controlkeel review plan submit --stdin --json" in examples
  end

  test "format json also requests machine-readable parse errors" do
    assert {:error, message} = CLI.parse(["route-agent", "--bad", "--format", "json"])

    assert %{
             "code" => "invalid_option",
             "command" => "route-agent",
             "help_topic" => "run",
             "details" => %{"invalid_options" => ["--bad"]}
           } = decode_cli_json(message)
  end

  test "text parse errors remain human-readable by default" do
    assert {:error, message} = CLI.parse(["status", "--bad"])

    assert message =~ "Unknown option(s): --bad for controlkeel status"
    assert message =~ "Use:"
    assert message =~ "Help:"
    assert_raise Jason.DecodeError, fn -> Jason.decode!(message) end
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

  describe "doctor command" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "controlkeel-doctor-#{System.unique_integer([:positive])}")

      File.rm_rf!(tmp_dir)
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      {:ok, tmp_dir: tmp_dir}
    end

    test "parses and renders a missing-binding text readiness packet", %{tmp_dir: tmp_dir} do
      assert {:ok, %{command: :doctor}} = CLI.parse(["doctor"])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert 0 ==
                   CLI.execute(%{command: :doctor, options: %{}, args: []}, project_root: tmp_dir)
        end)

      assert output =~ "ControlKeel doctor"
      assert output =~ "Binding: missing"
      assert output =~ "Next steps:"
      assert output =~ "controlkeel init"
    end

    test "doctor --json returns stable readiness sections", %{tmp_dir: tmp_dir} do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert 0 ==
                   CLI.execute(%{command: :doctor, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      payload = decode_cli_json(output)

      assert payload["status"] == "ok"
      assert payload["version"]
      assert Path.basename(payload["project_root"]) == Path.basename(tmp_dir)
      assert %{"status" => "missing"} = payload["binding"]
      assert is_map(payload["provider"])
      assert is_map(payload["agents"])
      assert is_map(payload["sandbox"])
      assert is_map(payload["capabilities"])
      assert "controlkeel init" in payload["next_steps"]
    end

    test "doctor catalog entry is read-only and json capable" do
      entry = Catalog.for_command(:doctor)

      assert entry.family == :core
      assert :json in entry.outputs
      refute entry.safety.mutates
      refute entry.safety.local_write
    end
  end

  describe "capabilities command" do
    test "parses and renders compact text summary" do
      assert {:ok, %{command: :capabilities}} = CLI.parse(["capabilities"])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert 0 == CLI.execute(%{command: :capabilities, options: %{}, args: []})
        end)

      assert output =~ "ControlKeel capabilities"
      assert output =~ "Commands:"
      assert output =~ "Hosts:"
      assert output =~ "controlkeel capabilities --json"
    end

    test "capabilities --json returns connected capability map" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert 0 == CLI.execute(%{command: :capabilities, options: %{json: true}, args: []})
        end)

      payload = decode_cli_json(output)

      assert is_list(payload["commands"])
      assert is_list(payload["families"])
      assert is_list(payload["hosts"])
      assert is_list(payload["mcp_tools"])
      assert is_list(payload["skills"])
      assert is_list(payload["hooks"])
      assert is_list(payload["plugins"])
      assert is_map(payload["automation"])

      assert Enum.any?(payload["commands"], &(&1["command"] == "capabilities"))
      assert "ck_validate" in payload["mcp_tools"]
      assert "controlkeel-governance" in payload["skills"]
      assert "PreToolUse" in payload["hooks"]
      assert "codex" in payload["plugins"]
    end

    test "capabilities includes every attachable host" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert 0 == CLI.execute(%{command: :capabilities, options: %{json: true}, args: []})
        end)

      host_ids = decode_cli_json(output) |> Map.fetch!("hosts") |> Enum.map(& &1["id"])

      for agent <- Integration.attachable_ids() do
        assert agent in host_ids
      end
    end

    test "capabilities catalog entry is read-only and json capable" do
      entry = Catalog.for_command(:capabilities)

      assert entry.family == :core
      assert :json in entry.outputs
      refute entry.safety.mutates
      refute entry.safety.local_write
    end
  end
end
