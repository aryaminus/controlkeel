defmodule ControlKeel.CLI.DetachTest do
  use ControlKeel.DataCase

  import ExUnit.CaptureIO

  alias ControlKeel.CLI
  alias ControlKeel.CLI.CodexConfig
  alias ControlKeel.Project.Local
  alias ControlKeel.Project.Binding

  setup do
    tmp = Path.join(System.tmp_dir!(), "ck-detach-#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, binding, _session, _state} = Local.load_or_bootstrap(tmp)
    {:ok, tmp: tmp, binding: binding}
  end

  defp run_detach(tmp, agent, options \\ %{}) do
    capture_io(fn ->
      assert 0 ==
               CLI.execute(
                 %{
                   command: :detach,
                   args: [agent],
                   options: Map.put(options, :project_root, tmp)
                 },
                 project_root: tmp
               )
    end)
  end

  # Keep a second agent attached so the binding survives detach for assertions.
  defp attach_two(binding, tmp, agents) do
    updated =
      Enum.reduce(agents, binding, fn {key, attrs}, acc ->
        Binding.update_attached_agent(acc, key, attrs)
      end)

    {:ok, _} = Binding.write_effective(updated, tmp, mode: :project)
    :ok
  end

  test "detach works for agents attached under a now-aliased or removed id", %{
    tmp: tmp,
    binding: binding
  } do
    :ok =
      attach_two(binding, tmp, [
        {"gemini-cli", %{"ide" => "gemini-cli"}},
        {"aider", %{"ide" => "aider"}},
        {"cursor", %{"ide" => "cursor"}}
      ])

    {:ok, argv_detach} = ControlKeel.CLI.Parser.parse(["detach", "gemini-cli"])
    assert argv_detach.args == ["gemini-cli"]

    run_detach(tmp, "gemini-cli")
    run_detach(tmp, "aider")

    {:ok, reloaded, _session} = Local.load(tmp)
    assert Map.keys(reloaded["attached_agents"]) == ["cursor"]
  end

  test "detach removes only the controlkeel MCP entry, keeping other servers", %{
    tmp: tmp,
    binding: binding
  } do
    cursor = Path.join(tmp, ".cursor/mcp.json")
    File.mkdir_p!(Path.dirname(cursor))

    File.write!(
      cursor,
      Jason.encode!(%{
        "mcpServers" => %{
          "controlkeel" => %{"command" => "controlkeel"},
          "other" => %{"command" => "x"}
        }
      })
    )

    attach_two(binding, tmp, [
      {"cursor",
       %{
         "server_name" => "controlkeel",
         "ide" => "cursor",
         "config_path" => cursor,
         "scope" => "project"
       }},
      {"opencode", %{"server_name" => "controlkeel", "scope" => "user"}}
    ])

    run_detach(tmp, "cursor")

    config = Jason.decode!(File.read!(cursor))
    refute Map.has_key?(config["mcpServers"], "controlkeel")
    assert Map.has_key?(config["mcpServers"], "other")

    {:ok, reloaded, _mode} = Binding.read_effective(tmp)
    refute Map.has_key?(reloaded["attached_agents"] || %{}, "cursor")
    assert Map.has_key?(reloaded["attached_agents"] || %{}, "opencode")
  end

  test "detach resolves the stored key when attach used a dash/underscore variant", %{
    tmp: tmp,
    binding: binding
  } do
    # attach stores claude-code under "claude_code"; detaching "claude-code" must resolve it.
    attach_two(binding, tmp, [
      {"claude_code", %{"server_name" => "controlkeel", "scope" => "local"}},
      {"opencode", %{"server_name" => "controlkeel", "scope" => "user"}}
    ])

    # claude binary absent -> MCP removal degrades to a no-op, detach still succeeds.
    System.put_env("CONTROLKEEL_CLAUDE_BIN", "ck-no-such-claude-binary")
    on_exit(fn -> System.delete_env("CONTROLKEEL_CLAUDE_BIN") end)

    run_detach(tmp, "claude-code")

    {:ok, reloaded, _mode} = Binding.read_effective(tmp)
    refute Map.has_key?(reloaded["attached_agents"] || %{}, "claude_code")
    assert Map.has_key?(reloaded["attached_agents"] || %{}, "opencode")
  end

  test "detach --json returns structured payload instead of text", %{tmp: tmp, binding: binding} do
    attach_two(binding, tmp, [
      {"opencode", %{"server_name" => "controlkeel", "scope" => "project"}},
      {"cursor", %{"server_name" => "controlkeel", "scope" => "user"}}
    ])

    output = run_detach(tmp, "opencode", %{json: true})
    envelope = Jason.decode!(output)
    payload = envelope["data"]

    assert envelope["status"] == "ok"
    assert payload["agent"] == "opencode"
    assert payload["scope"] == "project"
    assert payload["remaining_attached_agents"] == 1
  end

  test "detach removes CK-owned non-skill opencode artifacts but preserves user files", %{
    tmp: tmp,
    binding: binding
  } do
    opencode = Path.join(tmp, ".opencode")
    skills = Path.join(opencode, "skills")
    agents = Path.join(opencode, "agents")
    commands = Path.join(opencode, "commands")
    plugins = Path.join(opencode, "plugins")
    mcp = Path.join(opencode, "mcp.json")

    Enum.each([skills, agents, commands, plugins], &File.mkdir_p!/1)
    File.write!(Path.join(skills, ".controlkeel-skills.json"), Jason.encode!(%{"skills" => []}))
    File.write!(Path.join(agents, "controlkeel-operator.md"), "ck agent")
    File.write!(Path.join(commands, "controlkeel-review.md"), "ck command")
    File.write!(Path.join(commands, "user-command.md"), "user command")
    File.write!(Path.join(plugins, "controlkeel-governance.ts"), "ck plugin")
    File.write!(mcp, Jason.encode!(%{"mcp" => %{"controlkeel" => %{}}}))

    attach_two(binding, tmp, [
      {"opencode",
       %{
         "server_name" => "controlkeel",
         "scope" => "project",
         "target" => "opencode-native",
         "destination" => opencode,
         "skills_destination" => skills,
         "agents_destination" => agents,
         "commands_destination" => commands,
         "plugins_destination" => plugins,
         "mcp_destination" => mcp
       }},
      {"cursor", %{"server_name" => "controlkeel", "scope" => "user"}}
    ])

    run_detach(tmp, "opencode")

    refute File.exists?(skills)
    refute File.exists?(Path.join(agents, "controlkeel-operator.md"))
    refute File.exists?(Path.join(commands, "controlkeel-review.md"))
    refute File.exists?(Path.join(plugins, "controlkeel-governance.ts"))
    refute File.exists?(mcp)
    assert File.exists?(Path.join(commands, "user-command.md"))
  end

  test "agents doctor and attach doctor honor --json", %{tmp: tmp} do
    agents_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{
                     command: :agents_doctor,
                     args: [],
                     options: %{project_root: tmp, json: true}
                   },
                   project_root: tmp
                 )
      end)

    agents_payload = Jason.decode!(agents_output)
    assert agents_payload["status"] == "ok"
    assert is_list(agents_payload["data"]["agents"])

    attach_output =
      capture_io(fn ->
        assert 0 ==
                 CLI.execute(
                   %{
                     command: :attach_doctor,
                     args: [],
                     options: %{project_root: tmp, json: true}
                   },
                   project_root: tmp
                 )
      end)

    attach_payload = Jason.decode!(attach_output)
    assert attach_payload["status"] == "ok"
    assert is_list(attach_payload["data"]["attached_agents"])
  end

  test "detaching an agent that was never attached reports a clear error", %{tmp: tmp} do
    output =
      capture_io(:stderr, fn ->
        refute 0 ==
                 CLI.execute(
                   %{command: :detach, args: ["cursor"], options: %{project_root: tmp}},
                   project_root: tmp
                 )
      end)

    assert output =~ "not attached"
  end

  test "CodexConfig.remove strips the managed block but preserves user content", %{tmp: tmp} do
    path = Path.join(tmp, "config.toml")
    {:ok, _} = CodexConfig.write(path, %{command: "controlkeel", args: ["mcp"]})
    File.write!(path, "model = \"gpt-x\"\n" <> File.read!(path))

    assert File.read!(path) =~ "mcp_servers.controlkeel"

    assert :ok = CodexConfig.remove(path)
    remaining = File.read!(path)
    refute remaining =~ "mcp_servers.controlkeel"
    refute remaining =~ "controlkeel:start"
    assert remaining =~ "model = \"gpt-x\""
  end
end
