defmodule ControlKeel.CLIRuntimeTest do
  use ControlKeel.DataCase

  import ControlKeel.BenchmarkFixtures
  import ExUnit.CaptureIO
  import ControlKeel.MissionFixtures
  import ControlKeel.PlatformFixtures

  alias ControlKeel.Analytics
  alias ControlKeel.Benchmark
  alias ControlKeel.CLI
  alias ControlKeel.Platform
  alias ControlKeel.Project.Binding
  alias ControlKeel.Project.Root

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
    assert {:ok, %{command: :update}} = CLI.parse(["update"])
    assert {:ok, %{command: :update}} = CLI.parse(["upgrade", "--sync-attached"])
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

  test "guided help routes not connected questions to troubleshooting topic" do
    help_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{
                   command: :help,
                   options: %{},
                   args: ["ck_context", "not", "connected"]
                 })
      end)

    assert help_output =~ "Matched topic: MCP troubleshooting"
    assert help_output =~ "controlkeel attach doctor"
    assert help_output =~ "controlkeel provider doctor"
  end

  test "unknown commands return guided help suggestions" do
    assert {:error, message} = CLI.parse(["codx", "attach"])
    assert message =~ "Unknown command: controlkeel codx attach"
    assert message =~ "controlkeel help codx attach"
  end

  test "session list and switch expose mission switching for a bound project", %{tmp_dir: tmp_dir} do
    first = session_fixture(%{title: "First local mission", risk_tier: "low"})
    second = session_fixture(%{title: "Second local mission", risk_tier: "high"})

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => first.workspace_id,
                 "session_id" => first.id,
                 "agent" => "claude",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    assert {:ok, %{command: :session_list}} = CLI.parse(["session", "list"])

    assert {:ok, %{command: :session_switch, args: [id]}} =
             CLI.parse(["session", "switch", Integer.to_string(second.id)])

    assert id == Integer.to_string(second.id)

    list_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :session_list, options: %{}, args: []},
                   project_root: tmp_dir
                 )
      end)

    assert list_output =~ "Recent missions"
    assert list_output =~ "First local mission"
    assert list_output =~ "Second local mission"

    switch_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{
                     command: :session_switch,
                     options: %{},
                     args: [Integer.to_string(second.id)]
                   },
                   project_root: tmp_dir
                 )
      end)

    assert switch_output =~ "Switched ControlKeel project binding to mission ##{second.id}"

    assert {:ok, updated_binding} = Binding.read(tmp_dir)
    assert updated_binding["session_id"] == second.id
    assert updated_binding["workspace_id"] == second.workspace_id

    status_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :status, options: %{}, args: []}, project_root: tmp_dir)
      end)

    assert status_output =~ "Second local mission"
    refute status_output =~ "First local mission"
  end

  test "session switch reports missing missions without changing the binding", %{tmp_dir: tmp_dir} do
    first = session_fixture(%{title: "Only local mission"})

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => first.workspace_id,
                 "session_id" => first.id,
                 "agent" => "claude",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    switch_output =
      capture_io(:stderr, fn ->
        assert 1 ==
                 CLI.execute(
                   %{command: :session_switch, options: %{}, args: ["99999999"]},
                   project_root: tmp_dir
                 )
      end)

    assert switch_output =~ "Mission not found: 99999999"
    assert {:ok, binding} = Binding.read(tmp_dir)
    assert binding["session_id"] == first.id
  end

  test "guided help explains session switching" do
    help_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{
                   command: :help,
                   options: %{},
                   args: ["switch", "mission"]
                 })
      end)

    assert help_output =~ "Matched topic: Sessions and mission switching"
    assert help_output =~ "controlkeel session list"
    assert help_output =~ "controlkeel session switch <mission-id>"
  end

  test "session switch works from a nested folder and writes the project root binding", %{
    tmp_dir: tmp_dir
  } do
    first = session_fixture(%{title: "Nested first mission"})
    second = session_fixture(%{title: "Nested second mission"})
    nested_dir = Path.join(tmp_dir, "apps/web/lib")
    File.mkdir_p!(nested_dir)
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Nested.MixProject do\nend\n")

    assert {:ok, _binding} =
             Binding.write(
               %{
                 "workspace_id" => first.workspace_id,
                 "session_id" => first.id,
                 "agent" => "claude",
                 "attached_agents" => %{}
               },
               tmp_dir
             )

    output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{
                     command: :session_switch,
                     options: %{},
                     args: [Integer.to_string(second.id)]
                   },
                   project_root: nested_dir
                 )
      end)

    assert output =~ "Nested second mission"
    assert {:ok, binding} = Binding.read(tmp_dir)
    assert binding["session_id"] == second.id
    assert binding["project_root"] == Root.resolve(tmp_dir)
  end

  test "session switch keeps unrelated folder bindings isolated", %{tmp_dir: tmp_dir} do
    first_root = Path.join(tmp_dir, "project-a")
    second_root = Path.join(tmp_dir, "project-b")
    File.mkdir_p!(first_root)
    File.mkdir_p!(second_root)
    File.write!(Path.join(first_root, "mix.exs"), "defmodule A.MixProject do\nend\n")
    File.write!(Path.join(second_root, "mix.exs"), "defmodule B.MixProject do\nend\n")

    first = session_fixture(%{title: "Project A mission"})
    second = session_fixture(%{title: "Project B mission"})
    target = session_fixture(%{title: "Project A switched mission"})

    assert {:ok, _} =
             Binding.write(
               %{
                 "workspace_id" => first.workspace_id,
                 "session_id" => first.id,
                 "agent" => "claude",
                 "attached_agents" => %{}
               },
               first_root
             )

    assert {:ok, _} =
             Binding.write(
               %{
                 "workspace_id" => second.workspace_id,
                 "session_id" => second.id,
                 "agent" => "claude",
                 "attached_agents" => %{}
               },
               second_root
             )

    capture_io(fn ->
      assert 0 ==
               CLI.execute(
                 %{command: :session_switch, options: %{}, args: [Integer.to_string(target.id)]},
                 project_root: first_root
               )
    end)

    assert {:ok, first_binding} = Binding.read(first_root)
    assert {:ok, second_binding} = Binding.read(second_root)
    assert first_binding["session_id"] == target.id
    assert second_binding["session_id"] == second.id
  end

  test "session switch reports corrupt project bindings", %{tmp_dir: tmp_dir} do
    target = session_fixture(%{title: "Target mission"})
    File.mkdir_p!(Path.join(tmp_dir, "controlkeel"))
    File.write!(Path.join(tmp_dir, "controlkeel/project.json"), "not-json")

    output =
      capture_io(:stderr, fn ->
        assert 1 ==
                 CLI.execute(
                   %{
                     command: :session_switch,
                     options: %{},
                     args: [Integer.to_string(target.id)]
                   },
                   project_root: tmp_dir
                 )
      end)

    assert output =~ "Could not switch mission"
  end

  test "skills list supports json output", %{tmp_dir: tmp_dir} do
    assert {:ok, skills_list} = CLI.parse(["skills", "list", "--json"])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(skills_list, project_root: tmp_dir)
      end)

    payload = decode_cli_json(output)

    assert payload["project_root"] == Root.resolve(tmp_dir)
    assert is_list(payload["skills"])

    assert Enum.any?(payload["skills"], fn skill ->
             skill["name"] == "controlkeel-governance" and
               is_list(skill["compatibility_targets"]) and
               is_list(skill["required_mcp_tools"])
           end)
  end

  test "runtime init and status use the packaged CLI path", %{tmp_dir: tmp_dir} do
    assert {:ok, init} = CLI.parse(["init"])
    init_output = capture_io(fn -> assert 0 == CLI.execute(init, project_root: tmp_dir) end)

    assert init_output =~ "Initialized ControlKeel"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/bin/controlkeel-mcp"))
    assert {:ok, _binding} = Binding.read(tmp_dir)

    session = session_fixture(%{title: "Runtime CLI session"})
    task = task_fixture(%{session: session, title: "Patch auth flow", status: "queued"})

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

    assert {:ok, status_json} = CLI.parse(["status", "--json"])

    status_json_output =
      capture_io(fn ->
        assert 0 == CLI.execute(status_json, project_root: tmp_dir)
      end)

    assert {:ok, status_envelope} = Jason.decode(String.trim(status_json_output))
    status_payload = status_envelope["data"]
    assert get_in(status_payload, ["session", "title"]) == "Runtime CLI session"
    assert get_in(status_payload, ["autonomy_profile", "mode"])
    assert is_list(status_payload["suggested_next_steps"])

    assert {:ok, ctx} =
             CLI.parse(["context", "--session-id", Integer.to_string(session.id), "--json"])

    ctx_output =
      capture_io(fn ->
        assert 0 == CLI.execute(ctx, project_root: tmp_dir)
      end)

    assert {:ok, ctx_envelope} = Jason.decode(String.trim(ctx_output))
    ctx_payload = ctx_envelope["data"]
    assert ctx_payload["session_id"] == session.id

    assert {:ok, val} =
             CLI.parse([
               "validate",
               "--content",
               "echo hello",
               "--kind",
               "shell",
               "--json"
             ])

    val_output =
      capture_io(fn ->
        assert 0 == CLI.execute(val, project_root: tmp_dir)
      end)

    assert {:ok, val_envelope} = Jason.decode(String.trim(val_output))
    val_payload = val_envelope["data"]
    assert is_binary(val_payload["decision"])
  end

  test "findings output includes aggregates, filters, and next steps", %{tmp_dir: tmp_dir} do
    session = session_fixture(%{title: "Findings CLI session"})

    {:ok, _binding} =
      Binding.write(
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

    assert {:ok, findings_envelope} = Jason.decode(String.trim(findings_json_output))
    findings_payload = findings_envelope["data"]
    assert get_in(findings_payload, ["summary", "matched"]) == 1
    assert [%{"title" => "Patch validation missing"}] = findings_payload["entries"]
  end

  test "mcp accepts --project-root explicitly", %{tmp_dir: tmp_dir} do
    assert {:ok, parsed} = CLI.parse(["mcp", "--project-root", tmp_dir])
    assert parsed.command == :mcp
    assert parsed.options[:project_root] == tmp_dir
  end

  test "attach rejects unsupported scope per host" do
    assert {:error, message} = CLI.parse(["attach", "cursor", "--scope", "user"])
    assert message =~ "Unsupported scope"
    assert message =~ "Cursor"

    assert {:ok, _parsed} = CLI.parse(["attach", "codex-cli", "--scope", "user"])
  end

  test "attach doctor parses and runs", %{tmp_dir: tmp_dir} do
    assert {:ok, init} = CLI.parse(["init", "--no-attach"])

    capture_io(fn ->
      assert 0 == CLI.execute(init, project_root: tmp_dir)
    end)

    assert {:ok, parsed} = CLI.parse(["attach", "doctor", "--project-root", tmp_dir])
    assert parsed.command == :attach_doctor

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(parsed, project_root: tmp_dir)
      end)

    assert output =~ "Attach health check"
    assert output =~ "Verification commands:"
    assert output =~ "controlkeel provider doctor"
  end

  test "init and project-scoped codex attach accept --project-root explicitly", %{
    tmp_dir: tmp_dir
  } do
    assert {:ok, init} = CLI.parse(["init", "--project-root", tmp_dir, "--no-attach"])
    assert init.command == :init
    assert init.options[:project_root] == tmp_dir

    init_output =
      capture_io(fn ->
        assert 0 == CLI.execute(init, project_root: tmp_dir)
      end)

    assert init_output =~ "Initialized ControlKeel"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/project.json"))

    assert {:ok, attach} =
             CLI.parse([
               "attach",
               "codex-cli",
               "--project-root",
               tmp_dir,
               "--scope",
               "project"
             ])

    assert attach.command == :attach
    assert attach.options[:project_root] == tmp_dir
    assert attach.options[:scope] == "project"

    attach_output =
      capture_io(fn ->
        assert 0 == CLI.execute(attach, project_root: tmp_dir)
      end)

    assert attach_output =~ "Attached ControlKeel to Codex CLI."
    assert File.exists?(Path.join(tmp_dir, ".codex/config.toml"))
  end

  test "setup bootstraps from a nested directory and reports detected hosts", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Trial.MixProject do\nend\n")

    nested = Path.join(tmp_dir, "lib/trial")
    File.mkdir_p!(nested)

    File.mkdir_p!(
      Path.join([System.get_env("HOME") || System.user_home!(), ".config", "opencode"])
    )

    assert {:ok, parsed} = CLI.parse(["setup", "--project-root", nested])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(parsed, project_root: nested)
      end)

    resolved_root = Root.resolve(tmp_dir)

    assert output =~ "ControlKeel setup"
    assert output =~ "Project root: #{resolved_root}"
    assert output =~ "OpenCode"

    assert output =~
             "Core loop: ck_context -> ck_validate -> ck_review_submit/ck_finding -> ck_budget/ck_route/ck_delegate"

    assert output =~ "Attach next: controlkeel attach opencode"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/project.json"))
  end

  test "attach writes companion artifacts and prints install guidance", %{tmp_dir: _tmp_dir} do
    assert true
  end

  test "codex attach supports mcp-only mode without native bundle install", %{tmp_dir: tmp_dir} do
    assert {:ok, init} = CLI.parse(["init", "--no-attach"])

    capture_io(fn ->
      assert 0 == CLI.execute(init, project_root: tmp_dir)
    end)

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

    capture_io(fn ->
      assert 0 == CLI.execute(init, project_root: tmp_dir)
    end)

    {:ok, binding} = Binding.read(tmp_dir)

    {:ok, _binding} =
      Binding.write(
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

    {:ok, updated_binding} = Binding.read(tmp_dir)
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
    assert provider_list_output =~ "Trust boundary: no_provider_selected"

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

    capture_io(fn ->
      assert 0 == CLI.execute(set_key, project_root: tmp_dir)
      assert 0 == CLI.execute(set_base_url, project_root: tmp_dir)
      assert 0 == CLI.execute(set_model, project_root: tmp_dir)
      assert 0 == CLI.execute(provider_default, project_root: tmp_dir)
    end)

    assert {:ok, provider_show} = CLI.parse(["provider", "show", "--project-root", tmp_dir])

    provider_show_output =
      capture_io(fn ->
        assert 0 == CLI.execute(provider_show, project_root: tmp_dir)
      end)

    assert provider_show_output =~ "Selected source: user_default_profile"
    assert provider_show_output =~ "Selected provider: openai"
    assert provider_show_output =~ "Selected base URL: http://127.0.0.1:1234/v1"
    assert provider_show_output =~ "Trust boundary: openai_compatible_gateway"
    assert provider_show_output =~ "Intermediary risk: high"

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

  test "repo governance commands review patches, and check release readiness", %{
    tmp_dir: tmp_dir
  } do
    session = session_fixture(%{title: "Governed CLI session"})
    task = task_fixture(%{session: session, status: "done", title: "Release proof"})
    _proof = proof_bundle_fixture(%{task: task})

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
  end

  test "runtime export emits the Open SWE headless bundle", %{tmp_dir: tmp_dir} do
    assert {:ok, export} = CLI.parse(["runtime", "export", "open-swe", "--project-root", tmp_dir])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(export, project_root: tmp_dir)
      end)

    resolved_root = Root.resolve(tmp_dir)

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

    resolved_root = Root.resolve(tmp_dir)

    assert output =~ "Prepared Devin runtime export."
    assert output =~ "Project root: #{resolved_root}"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/devin-runtime/AGENTS.md"))
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/devin-runtime/devin/README.md"))

    assert File.exists?(
             Path.join(tmp_dir, "controlkeel/dist/devin-runtime/devin/controlkeel-mcp.json")
           )
  end

  test "runtime export emits the Executor headless bundle", %{tmp_dir: tmp_dir} do
    assert {:ok, export} = CLI.parse(["runtime", "export", "executor", "--project-root", tmp_dir])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(export, project_root: tmp_dir)
      end)

    resolved_root = Root.resolve(tmp_dir)

    assert output =~ "Prepared Executor runtime export."
    assert output =~ "Project root: #{resolved_root}"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/executor-runtime/AGENTS.md"))

    assert File.exists?(
             Path.join(tmp_dir, "controlkeel/dist/executor-runtime/executor/README.md")
           )

    assert File.exists?(
             Path.join(
               tmp_dir,
               "controlkeel/dist/executor-runtime/executor/controlkeel-sources.example.ts"
             )
           )
  end

  test "runtime export emits the Warp Oz headless bundle", %{tmp_dir: tmp_dir} do
    assert {:ok, export} = CLI.parse(["runtime", "export", "warp-oz", "--project-root", tmp_dir])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(export, project_root: tmp_dir)
      end)

    resolved_root = Root.resolve(tmp_dir)

    assert output =~ "Prepared Warp Oz runtime export."
    assert output =~ "Project root: #{resolved_root}"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/warp-oz-runtime/AGENTS.md"))
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/warp-oz-runtime/warp-oz/README.md"))

    assert File.exists?(
             Path.join(
               tmp_dir,
               "controlkeel/dist/warp-oz-runtime/warp-oz/controlkeel-agent-config.json"
             )
           )
  end

  test "runtime export emits the Cloudflare Workers headless bundle", %{tmp_dir: tmp_dir} do
    assert {:ok, export} =
             CLI.parse(["runtime", "export", "cloudflare-workers", "--project-root", tmp_dir])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(export, project_root: tmp_dir)
      end)

    resolved_root = Root.resolve(tmp_dir)

    assert output =~ "Prepared Cloudflare Workers runtime export."
    assert output =~ "Project root: #{resolved_root}"

    assert File.exists?(
             Path.join(tmp_dir, "controlkeel/dist/cloudflare-workers-runtime/AGENTS.md")
           )

    assert File.exists?(
             Path.join(
               tmp_dir,
               "controlkeel/dist/cloudflare-workers-runtime/cloudflare-workers/README.md"
             )
           )

    assert File.exists?(
             Path.join(
               tmp_dir,
               "controlkeel/dist/cloudflare-workers-runtime/cloudflare-workers/wrangler.toml"
             )
           )
  end

  test "runtime export emits the virtual bash headless bundle", %{tmp_dir: tmp_dir} do
    assert {:ok, export} =
             CLI.parse(["runtime", "export", "virtual-bash", "--project-root", tmp_dir])

    output =
      capture_io(fn ->
        assert 0 == CLI.execute(export, project_root: tmp_dir)
      end)

    resolved_root = Root.resolve(tmp_dir)

    assert output =~ "Prepared virtual bash runtime export."
    assert output =~ "Project root: #{resolved_root}"
    assert File.exists?(Path.join(tmp_dir, "controlkeel/dist/virtual-bash-runtime/AGENTS.md"))

    assert File.exists?(
             Path.join(tmp_dir, "controlkeel/dist/virtual-bash-runtime/virtual-bash/README.md")
           )

    assert File.exists?(
             Path.join(
               tmp_dir,
               "controlkeel/dist/virtual-bash-runtime/virtual-bash/controlkeel-runtime.json"
             )
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
      Binding.write(
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

    assert {:ok, proofs_envelope} = Jason.decode(String.trim(proofs_json_output))
    proofs_payload = proofs_envelope["data"]
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

  test "status refreshes stale claude and codex attachments with pre-existing destinations", %{
    tmp_dir: tmp_dir
  } do
    session = session_fixture(%{title: "CLI attached sync session"})

    {:ok, _binding} =
      Binding.write(
        %{
          "workspace_id" => session.workspace_id,
          "session_id" => session.id,
          "agent" => "claude",
          "attached_agents" => %{
            "claude_code" => %{
              "target" => "claude-standalone",
              "scope" => "user",
              "controlkeel_version" => "0.0.1"
            },
            "codex-cli" => %{
              "target" => "codex",
              "scope" => "project",
              "controlkeel_version" => "0.0.1"
            }
          }
        },
        tmp_dir
      )

    File.mkdir_p!(Path.join(tmp_dir, "controlkeel/dist/codex"))
    File.write!(Path.join(tmp_dir, "controlkeel/dist/codex/stale.txt"), "stale")

    File.mkdir_p!(Path.join(tmp_dir, "home/.claude/skills/cloudflare-agent"))

    File.write!(
      Path.join(tmp_dir, "home/.claude/skills/cloudflare-agent/SKILL.md"),
      "stale\n"
    )

    status_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(%{command: :status, options: %{}, args: []}, project_root: tmp_dir)
      end)

    assert status_output =~ "Attached agents:"
    assert status_output =~ "claude_code (CK v"
    assert status_output =~ "codex-cli (CK v"

    assert File.exists?(
             Path.join(
               tmp_dir,
               "home/.claude/skills/cloudflare-agent/references/cloudflare-integration.md"
             )
           )

    assert File.exists?(Path.join(tmp_dir, ".codex/config.toml"))
    refute File.exists?(Path.join(tmp_dir, "controlkeel/dist/codex/stale.txt"))
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

    assert {:ok, list_envelope} = Jason.decode(String.trim(list_json_output))
    list_payload = list_envelope["data"]
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

    org = ControlKeel.AccountsFixtures.org_fixture()
    workspace = workspace_fixture(%{org_id: org.id})
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

    policy_set = policy_set_fixture(%{org_id: org.id})

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
      capture_io(:stderr, fn ->
        assert 1 ==
                 CLI.execute(
                   %{command: :sandbox_config, options: %{adapter: "firecracker"}, args: []},
                   project_root: tmp_dir
                 )
      end)
    end

    test "agents discover with --json does not crash on keyword-list options", %{
      tmp_dir: tmp_dir
    } do
      # Regression: options from CLI parser are a keyword list, not a map.
      # Map.get/3 on a keyword list crashes with BadMapError.
      File.mkdir_p!(Path.join(tmp_dir, ".claude"))

      output =
        capture_io(fn ->
          CLI.execute(
            %{command: :agents_discover, args: [tmp_dir], options: [json: true]},
            project_root: tmp_dir
          )
        end)

      # Must produce valid JSON, not a crash dump
      assert Jason.decode(output) != {:error, %Jason.DecodeError{}}
    end
  end
end
