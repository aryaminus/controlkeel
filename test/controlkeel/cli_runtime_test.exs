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
  alias ControlKeel.ProjectRoot

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

    assert {:ok, %{command: :help, args: ["attach", "codex"]}} =
             CLI.parse(["help", "attach", "codex"])

    help_output =
      capture_io(fn ->
        assert 0 == CLI.execute(%{command: :help, options: %{}, args: []})
      end)

    version_output =
      capture_io(fn ->
        assert 0 == CLI.execute(%{command: :version, options: %{}, args: []})
      end)

    assert help_output =~ "ControlKeel help"
    assert help_output =~ "controlkeel help why is my task blocked"
    assert version_output =~ "ControlKeel"
  end

  test "guided help routes attach questions to the codex topic" do
    help_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{
                   command: :help,
                   options: %{},
                   args: ["how", "do", "i", "attach", "codex"]
                 })
      end)

    assert help_output =~ "Matched topic: Attach and host setup"
    assert help_output =~ "Matched agent: Codex CLI"
    assert help_output =~ "controlkeel attach codex-cli --scope project"
    assert help_output =~ ".codex/config.toml"
  end

  test "unknown commands return guided help suggestions" do
    assert {:error, message} = CLI.parse(["codx", "attach"])
    assert message =~ "Unknown command: controlkeel codx attach"
    assert message =~ "controlkeel help codx attach"
  end

  test "runtime init and status use the packaged CLI path", %{tmp_dir: tmp_dir} do
    assert {:ok, init} = CLI.parse(["init"])
    init_output = capture_io(fn -> assert 0 == CLI.execute(init, project_root: tmp_dir) end)

    assert init_output =~ "Initialized ControlKeel"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/bin/controlkeel-mcp"))
    assert {:ok, _binding} = ProjectBinding.read(tmp_dir)

    session = session_fixture(%{title: "Runtime CLI session"})
    task = task_fixture(%{session: session, title: "Patch auth flow", status: "queued"})

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

    finding_fixture(%{
      session: session,
      status: "blocked",
      title: "Runtime blocked finding",
      metadata: %{
        "finding_family" => "vulnerability_case",
        "affected_component" => "auth",
        "patch_status" => "drafted",
        "disclosure_status" => "triaged",
        "exploitability_status" => "suspected",
        "maintainer_scope" => "first_party"
      }
    })

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
    assert status_output =~ "Autonomy:"
    assert status_output =~ "Task augmentation:"
    assert status_output =~ "Security cases: 1 tracked"
    assert status_output =~ "Blocked findings:"
    assert status_output =~ "Suggested next steps:"
    assert status_output =~ "controlkeel proofs --task-id #{task.id}"

    assert {:ok, status_json} = CLI.parse(["status", "--format", "json"])

    status_json_output =
      capture_io(fn ->
        assert 0 == CLI.execute(status_json, project_root: tmp_dir)
      end)

    assert {:ok, status_payload} = Jason.decode(String.trim(status_json_output))
    assert get_in(status_payload, ["session", "title"]) == "Runtime CLI session"
    assert get_in(status_payload, ["autonomy_profile", "mode"])
    assert is_list(status_payload["suggested_next_steps"])
  end

  test "findings output includes aggregates, filters, and next steps", %{tmp_dir: tmp_dir} do
    session = session_fixture(%{title: "Findings CLI session"})

    {:ok, _binding} =
      ProjectBinding.write(
        %{
          "workspace_id" => session.workspace_id,
          "session_id" => session.id,
          "agent" => "codex-cli",
          "attached_agents" => %{}
        },
        tmp_dir
      )

    finding_fixture(%{
      session: session,
      severity: "high",
      status: "open",
      title: "Patch validation missing",
      metadata: %{
        "finding_family" => "vulnerability_case",
        "affected_component" => "ci",
        "patch_status" => "drafted",
        "disclosure_status" => "triaged",
        "exploitability_status" => "suspected",
        "maintainer_scope" => "first_party"
      }
    })

    assert {:ok, findings} = CLI.parse(["findings", "--severity", "high", "--status", "open"])

    findings_output =
      capture_io(fn ->
        assert 0 == CLI.execute(findings, project_root: tmp_dir)
      end)

    assert findings_output =~ "Findings: 1 matched (severity=high, status=open)"
    assert findings_output =~ "Security cases: 1 tracked"
    assert findings_output =~ "Patch validation missing"
    assert findings_output =~ "Suggested next steps:"
    assert findings_output =~ "controlkeel approve <finding_id>"

    assert {:ok, findings_json} =
             CLI.parse(["findings", "--severity", "high", "--status", "open", "--format", "json"])

    findings_json_output =
      capture_io(fn ->
        assert 0 == CLI.execute(findings_json, project_root: tmp_dir)
      end)

    assert {:ok, findings_payload} = Jason.decode(String.trim(findings_json_output))
    assert get_in(findings_payload, ["summary", "matched"]) == 1
    assert [%{"title" => "Patch validation missing"}] = findings_payload["entries"]
  end

  test "mcp accepts --project-root explicitly", %{tmp_dir: tmp_dir} do
    assert {:ok, parsed} = CLI.parse(["mcp", "--project-root", tmp_dir])
    assert parsed.command == :mcp
    assert parsed.options[:project_root] == tmp_dir
  end

  test "setup bootstraps from a nested directory and reports detected hosts", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Demo.MixProject do\nend\n")

    nested = Path.join(tmp_dir, "lib/demo")
    File.mkdir_p!(nested)

    File.mkdir_p!(
      Path.join([System.get_env("HOME") || System.user_home!(), ".config", "opencode"])
    )

    assert {:ok, parsed} = CLI.parse(["setup", "--project-root", nested])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(parsed, project_root: nested)
      end)

    resolved_root = ProjectRoot.resolve(tmp_dir)

    assert output =~ "ControlKeel setup"
    assert output =~ "Project root: #{resolved_root}"
    assert output =~ "OpenCode"

    assert output =~
             "Core loop: ck_context -> ck_validate -> ck_review_submit/ck_finding -> ck_budget/ck_route/ck_delegate"

    assert output =~ "Attach next: controlkeel attach opencode"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/project.json"))
  end

  test "plugin and delegated execution commands work", %{tmp_dir: tmp_dir} do
    assert {:ok, plugin_export} =
             CLI.parse(["plugin", "export", "codex", "--project-root", tmp_dir])

    export_output =
      capture_io(fn ->
        assert 0 == CLI.execute(plugin_export, project_root: tmp_dir)
      end)

    assert export_output =~ "Exported codex plugin bundle."

    assert File.exists?(
             Path.join(tmp_dir, "controlkeel/dist/codex-plugin/.codex-plugin/plugin.json")
           )

    assert {:ok, augment_plugin_export} =
             CLI.parse(["plugin", "export", "augment", "--project-root", tmp_dir])

    augment_export_output =
      capture_io(fn ->
        assert 0 == CLI.execute(augment_plugin_export, project_root: tmp_dir)
      end)

    assert augment_export_output =~ "Exported augment plugin bundle."

    assert File.exists?(
             Path.join(tmp_dir, "controlkeel/dist/augment-plugin/.augment-plugin/plugin.json")
           )

    assert {:ok, plugin_install} =
             CLI.parse([
               "plugin",
               "install",
               "codex",
               "--scope",
               "project",
               "--mode",
               "hosted",
               "--project-root",
               tmp_dir
             ])

    install_output =
      capture_io(fn ->
        assert 0 == CLI.execute(plugin_install, project_root: tmp_dir)
      end)

    assert install_output =~ "Installed codex plugin bundle."
    assert File.exists?(Path.join(tmp_dir, "plugins/controlkeel/.codex-plugin/plugin.json"))
    assert File.exists?(Path.join(tmp_dir, ".agents/plugins/marketplace.json"))

    session = session_fixture()
    task = task_fixture(%{session: session})

    assert {:ok, run_task} =
             CLI.parse([
               "run",
               "task",
               Integer.to_string(task.id),
               "--agent",
               "cursor",
               "--mode",
               "handoff",
               "--project-root",
               tmp_dir
             ])

    run_output =
      capture_io(fn ->
        assert 0 == CLI.execute(run_task, project_root: tmp_dir)
      end)

    assert run_output =~ "Delegated task ##{task.id}."
    assert run_output =~ "Status: waiting_callback"

    assert {:ok, doctor} = CLI.parse(["agents", "doctor", "--project-root", tmp_dir])

    doctor_output =
      capture_io(fn ->
        assert 0 == CLI.execute(doctor, project_root: tmp_dir)
      end)

    assert doctor_output =~ "Agent execution doctor"
    assert doctor_output =~ "Detected hosts:"
    assert doctor_output =~ "cursor: handoff / handoff"
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
    assert codex_output =~ "Installed Codex skills at "
    assert codex_output =~ ".codex/skills."
    assert codex_output =~ "Installed open-standard compatibility skills at "
    assert codex_output =~ ".agents/skills."
    assert codex_output =~ "Auth mode: agent_runtime."
    assert codex_output =~ "Provider bridge: agent_runtime: openai."
    assert File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".codex/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".codex/agents/controlkeel-operator.toml"))
    assert File.exists?(project_codex_config_path(tmp_dir))
    refute File.exists?(user_codex_config_path())

    codex_config = File.read!(project_codex_config_path(tmp_dir))
    assert codex_config =~ "[mcp_servers.controlkeel]"
    assert codex_config =~ ~s(config_file = "./agents/controlkeel-operator.toml")

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

    assert cursor_output =~ "Companion target: cursor-native."
    assert File.exists?(Path.join(tmp_dir, ".cursor/rules/controlkeel.mdc"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/mcp.json"))
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

    assert {:ok, kilo_attach} = CLI.parse(["attach", "kilo"])

    kilo_output =
      capture_io(fn ->
        assert 0 == CLI.execute(kilo_attach, project_root: tmp_dir)
      end)

    assert kilo_output =~ "Attached ControlKeel to Kilo Code."
    assert kilo_output =~ "Companion target: kilo-native."
    assert kilo_output =~ "Auth mode: ck_owned."
    assert File.exists?(kilo_config_path())
    assert File.exists?(Path.join(tmp_dir, ".kilo/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".kilo/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".kilo/kilo.json"))

    assert {:ok, kilo_config} = Jason.decode(File.read!(kilo_config_path()))
    assert get_in(kilo_config, ["mcp", "controlkeel", "type"]) == "local"
    assert get_in(kilo_config, ["mcp", "controlkeel", "enabled"]) == true

    kilo_cmd = get_in(kilo_config, ["mcp", "controlkeel", "command"])
    assert is_list(kilo_cmd)
    assert length(kilo_cmd) >= 1

    assert {:ok, roo_attach} = CLI.parse(["attach", "roo-code"])

    roo_output =
      capture_io(fn ->
        assert 0 == CLI.execute(roo_attach, project_root: tmp_dir)
      end)

    assert roo_output =~ "Prepared ControlKeel companion files for Roo Code."
    assert roo_output =~ "Companion target: roo-native."
    assert File.exists?(Path.join(tmp_dir, ".roo/skills/controlkeel-governance/SKILL.md"))
    assert File.exists?(Path.join(tmp_dir, ".roo/rules/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".roo/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".roo/guidance/controlkeel.md"))
    assert File.exists?(Path.join(tmp_dir, ".roomodes"))

    assert {:ok, goose_attach} = CLI.parse(["attach", "goose"])

    goose_output =
      capture_io(fn ->
        assert 0 == CLI.execute(goose_attach, project_root: tmp_dir)
      end)

    assert goose_output =~ "Attached ControlKeel to Goose."
    assert goose_output =~ "Companion target: goose-native."
    assert goose_output =~ "Auth mode: ck_owned."
    assert File.exists?(goose_config_path())
    assert File.exists?(Path.join(tmp_dir, ".goosehints"))
    assert File.exists?(Path.join(tmp_dir, "goose/workflow_recipes/controlkeel-review.yaml"))
    assert File.exists?(Path.join(tmp_dir, "goose/controlkeel-extension.yaml"))

    assert {:ok, goose_config} = YamlElixir.read_from_file(goose_config_path())
    assert goose_config["extensions"]["controlkeel"]["type"] == "stdio"

    assert goose_config["extensions"]["controlkeel"]["cmd"] == "controlkeel" or
             String.ends_with?(
               goose_config["extensions"]["controlkeel"]["cmd"],
               "/controlkeel/bin/controlkeel-mcp"
             )

    # Regression: attaching OpenCode should recover from malformed existing MCP config.
    File.mkdir_p!(Path.dirname(opencode_config_path()))
    File.write!(opencode_config_path(), "{\"mcpServers\": {\"broken\": ")

    assert {:ok, opencode_attach} = CLI.parse(["attach", "opencode"])

    opencode_output =
      capture_io(fn ->
        assert 0 == CLI.execute(opencode_attach, project_root: tmp_dir)
      end)

    assert opencode_output =~ "Attached ControlKeel to OpenCode."
    assert opencode_output =~ "Companion target: opencode-native."
    assert opencode_output =~ "Prepared native companion files for OpenCode."

    assert File.exists?(Path.join(tmp_dir, ".opencode/plugins/controlkeel-governance.ts"))
    assert File.exists?(Path.join(tmp_dir, ".opencode/agents/controlkeel-operator.md"))
    assert File.exists?(Path.join(tmp_dir, ".opencode/commands/controlkeel-review.md"))
    assert File.exists?(Path.join(tmp_dir, ".opencode/mcp.json"))

    assert {:ok, opencode_config} = Jason.decode(File.read!(opencode_config_path()))

    assert get_in(opencode_config, ["mcp", "controlkeel", "type"]) == "local"

    opencode_cmd = get_in(opencode_config, ["mcp", "controlkeel", "command"])
    assert is_list(opencode_cmd)
    assert length(opencode_cmd) >= 1

    assert hd(opencode_cmd) == "controlkeel" or
             String.ends_with?(hd(opencode_cmd), "/controlkeel/bin/controlkeel-mcp")
  end

  test "codex attach supports mcp-only mode without native bundle install", %{tmp_dir: tmp_dir} do
    assert {:ok, init} = CLI.parse(["init", "--no-attach"])
    assert 0 == CLI.execute(init, project_root: tmp_dir)

    assert {:ok, codex_attach} =
             CLI.parse(["attach", "codex-cli", "--scope", "project", "--mcp-only"])

    codex_output =
      capture_io(fn ->
        assert 0 == CLI.execute(codex_attach, project_root: tmp_dir)
      end)

    assert codex_output =~ "Attached ControlKeel to Codex CLI."
    assert File.exists?(project_codex_config_path(tmp_dir))
    refute codex_output =~ "Installed Codex skills"
    refute File.exists?(Path.join(tmp_dir, ".agents/skills/controlkeel-governance/SKILL.md"))
    refute File.exists?(Path.join(tmp_dir, ".codex/agents/controlkeel-operator.toml"))
    refute File.exists?(Path.join(tmp_dir, ".codex/commands/controlkeel-review.md"))
  end

  test "user-scoped codex attach does not sync stale project-native agents", %{tmp_dir: tmp_dir} do
    assert {:ok, init} = CLI.parse(["init", "--no-attach"])
    assert 0 == CLI.execute(init, project_root: tmp_dir)

    {:ok, binding} = ProjectBinding.read(tmp_dir)

    {:ok, _binding} =
      ProjectBinding.write(
        put_in(binding, ["attached_agents", "opencode"], %{
          "ide" => "opencode",
          "target" => "opencode-native",
          "scope" => "project",
          "controlkeel_version" => "0.0.1"
        }),
        tmp_dir
      )

    File.write!(Path.join(tmp_dir, "AGENTS.md"), "# Repo instructions\n")

    assert {:ok, codex_attach} = CLI.parse(["attach", "codex-cli", "--scope", "user"])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(codex_attach, project_root: tmp_dir)
      end)

    assert output =~ "Attached ControlKeel to Codex CLI."
    assert output =~ "MCP server written to #{user_codex_config_path()}."

    assert File.exists?(user_codex_config_path())
    refute File.exists?(Path.join(tmp_dir, ".opencode"))
    refute File.exists?(Path.join(tmp_dir, ".codex"))
    refute File.exists?(Path.join(tmp_dir, ".agents"))
    refute File.exists?(Path.join(tmp_dir, ".mcp.json"))
    assert File.read!(Path.join(tmp_dir, "AGENTS.md")) == "# Repo instructions\n"

    {:ok, updated_binding} = ProjectBinding.read(tmp_dir)
    refute get_in(updated_binding, ["attached_agents", "opencode", "synced_at"])
    assert get_in(updated_binding, ["attached_agents", "codex-cli", "scope"]) == "user"
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
    assert File.exists?(Path.join(tmp_dir, ".cursor/rules/controlkeel.mdc"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/mcp.json"))

    assert {:ok, bootstrap} = CLI.parse(["bootstrap", "--project-root", tmp_dir])

    bootstrap_output =
      capture_io(fn ->
        assert 0 == CLI.execute(bootstrap, project_root: tmp_dir)
      end)

    assert bootstrap_output =~ "Bootstrapped ControlKeel"
    assert bootstrap_output =~ "Binding mode: existing"
    assert bootstrap_output =~ "Detected hosts:"
  end

  test "runtime export emits the Open SWE headless bundle", %{tmp_dir: tmp_dir} do
    assert {:ok, export} = CLI.parse(["runtime", "export", "open-swe", "--project-root", tmp_dir])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(export, project_root: tmp_dir)
      end)

    resolved_root = ProjectRoot.resolve(tmp_dir)

    assert output =~ "Prepared Open SWE runtime export."
    assert output =~ "Project root: #{resolved_root}"
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

    resolved_root = ProjectRoot.resolve(tmp_dir)

    assert output =~ "Prepared Devin runtime export."
    assert output =~ "Project root: #{resolved_root}"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/devin-runtime/AGENTS.md"))
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/devin-runtime/devin/README.md"))

    assert File.exists?(
             Path.join(tmp_dir, "controlkeel/dist/devin-runtime/devin/controlkeel-mcp.json")
           )
  end

  test "repo governance commands review patches, check release readiness, and scaffold github", %{
    tmp_dir: tmp_dir
  } do
    session = session_fixture(%{title: "Governed CLI session"})
    task = task_fixture(%{session: session, status: "done", title: "Release proof"})
    _proof = proof_bundle_fixture(%{task: task})

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

    patch_path = Path.join(tmp_dir, "review.patch")

    patch = """
    diff --git a/lib/auth.ex b/lib/auth.ex
    index 1111111..2222222 100644
    --- a/lib/auth.ex
    +++ b/lib/auth.ex
    @@ -0,0 +1,1 @@
    +api_key = "AKIAIOSFODNN7EXAMPLE"
    """

    assert :ok == File.write(patch_path, patch)

    assert {:ok, review_pr} = CLI.parse(["review", "pr", "--patch", patch_path])

    review_output =
      capture_io(fn ->
        assert 0 == CLI.execute(review_pr, project_root: tmp_dir)
      end)

    assert review_output =~ "Merge recommendation: blocked."
    assert review_output =~ "secret.aws_access_key"

    socket_report_path = Path.join(tmp_dir, "socket-report.json")

    socket_report =
      Jason.encode!(%{
        "issues" => [
          %{
            "package" => "left-pad",
            "severity" => "high",
            "summary" => "Known malicious postinstall behavior",
            "manifest_path" => "package-lock.json",
            "id" => "socket-alert-123"
          }
        ]
      })

    assert :ok == File.write(socket_report_path, socket_report)

    assert {:ok, review_socket} =
             CLI.parse(["review", "socket", "--report", socket_report_path])

    socket_output =
      capture_io(fn ->
        assert 0 == CLI.execute(review_socket, project_root: tmp_dir)
      end)

    assert socket_output =~ "Dependency recommendation: blocked."
    assert socket_output =~ "dependencies.socket.alert"
    assert socket_output =~ "left-pad: Known malicious postinstall behavior"

    assert {:ok, release_ready} =
             CLI.parse([
               "release-ready",
               "--sha",
               "abc123",
               "--smoke-status",
               "success",
               "--artifact-source",
               "github-actions",
               "--provenance-verified"
             ])

    release_output =
      capture_io(fn ->
        assert 0 == CLI.execute(release_ready, project_root: tmp_dir)
      end)

    assert release_output =~ "Release readiness: blocked"

    assert {:ok, govern_install} = CLI.parse(["govern", "install", "github"])

    govern_output =
      capture_io(fn ->
        assert 0 == CLI.execute(govern_install, project_root: tmp_dir)
      end)

    assert govern_output =~ "Installed ControlKeel GitHub governance scaffolding."
    assert File.exists?(Path.join(tmp_dir, ".github/workflows/controlkeel-pr-governor.yml"))
    assert File.exists?(Path.join(tmp_dir, ".github/workflows/controlkeel-release-governor.yml"))
    assert File.exists?(Path.join(tmp_dir, ".github/workflows/scorecards.yml"))
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

    assert proofs_output =~ "Proof bundles: 1 matched"
    assert proofs_output =~ "Deploy-ready in view:"
    assert proofs_output =~ "CLI proof task"
    assert proofs_output =~ "Suggested next steps:"

    proofs_json_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{command: :proofs, options: %{format: "json"}, args: []},
                   project_root: tmp_dir
                 )
      end)

    assert {:ok, proofs_payload} = Jason.decode(String.trim(proofs_json_output))
    assert get_in(proofs_payload, ["summary", "matched"]) == 1
    assert [%{"task_title" => "CLI proof task"}] = proofs_payload["entries"]

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
    assert list_output =~ "Available subjects:"
    assert list_output =~ "Recent runs:"
    assert list_output =~ "Benchmark suites:"
    assert list_output =~ "manual_subject"
    assert list_output =~ "domain_expansion_v1"
    assert list_output =~ "Suggested next steps:"
    refute list_output =~ "vibe_failures_v1"

    assert {:ok, list_json} =
             CLI.parse(["benchmark", "list", "--domain-pack", "hr", "--format", "json"])

    list_json_output =
      capture_io(fn ->
        assert 0 == CLI.execute(list_json, project_root: tmp_dir)
      end)

    assert {:ok, list_payload} = Jason.decode(String.trim(list_json_output))
    assert get_in(list_payload, ["summary", "suite_count"]) >= 1
    assert Enum.any?(list_payload["subjects"], &(&1["id"] == "manual_subject"))

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
    assert show_output =~ "Suggested next steps:"

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
    assert account_output =~ "OAuth client id: ck-sa-"

    list_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{
                     command: :service_account_list,
                     options: [workspace_id: workspace.id],
                     args: []
                   },
                   project_root: tmp_dir
                 )
      end)

    assert list_output =~ "Service accounts for workspace"
    assert list_output =~ "client: ck-sa-"

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

  defp user_codex_config_path do
    home = System.get_env("HOME") || System.user_home!()

    case :os.type() do
      {:win32, _} -> Path.join([System.get_env("APPDATA") || home, ".codex", "config.toml"])
      _ -> Path.join([home, ".codex", "config.toml"])
    end
  end

  defp project_codex_config_path(project_root) do
    Path.join([project_root, ".codex", "config.toml"])
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

  defp goose_config_path do
    Path.join([System.get_env("HOME") || System.user_home!(), ".config", "goose", "config.yaml"])
  end

  defp opencode_config_path do
    Path.join([
      System.get_env("HOME") || System.user_home!(),
      ".config",
      "opencode",
      "config.json"
    ])
  end

  defp kilo_config_path do
    Path.join([
      System.get_env("HOME") || System.user_home!(),
      ".config",
      "kilo",
      "kilo.json"
    ])
  end

  describe "sandbox commands" do
    setup do
      tmp_dir = System.tmp_dir!() |> Path.join("controlkeel-test-#{:rand.uniform(100_000)}")
      File.rm_rf!(tmp_dir)
      File.mkdir_p!(tmp_dir)
      {:ok, tmp_dir: tmp_dir}
    end

    test "sandbox status shows adapter availability", %{tmp_dir: tmp_dir} do
      output =
        capture_io(fn ->
          CLI.execute(%{command: :sandbox_status, options: %{}, args: []}, project_root: tmp_dir)
        end)

      assert output =~ "Execution sandbox adapters"
      assert output =~ "local"
      assert output =~ "docker"
      assert output =~ "e2b"
      assert output =~ "nono"
    end

    test "sandbox config sets adapter", %{tmp_dir: tmp_dir} do
      output =
        capture_io(fn ->
          CLI.execute(%{command: :sandbox_config, options: %{adapter: "nono"}, args: []},
            project_root: tmp_dir
          )
        end)

      assert output =~ "Execution sandbox set to: nono"
    end

    test "sandbox config rejects unknown adapter", %{tmp_dir: tmp_dir} do
      exit_code =
        CLI.execute(%{command: :sandbox_config, options: %{adapter: "firecracker"}, args: []},
          project_root: tmp_dir
        )

      assert exit_code == 1
    end
  end
end
