defmodule ControlKeel.DocsConsistencyTest do
  use ExUnit.Case, async: true

  alias ControlKeel.AgentIntegration
  alias ControlKeel.Distribution

  @repo_root Path.expand("../..", __DIR__)

  test "README install section stays aligned with the canonical install channels" do
    readme = read_doc!("README.md")

    assert readme =~ Distribution.install_channel("homebrew").command
    assert readme =~ Distribution.install_channel("npm").command
    assert readme =~ Distribution.install_channel("shell-installer").command
    assert readme =~ Distribution.install_channel("powershell-installer").command
  end

  test "codex family docs stay aligned with the typed integration catalog" do
    direct_installs = read_doc!("docs/direct-host-installs.md")
    integrations = read_doc!("docs/agent-integrations.md")

    codex_cli = AgentIntegration.get("codex-cli")
    codex_app_server = AgentIntegration.get("codex-app-server")
    t3code = AgentIntegration.get("t3code")

    assert codex_cli.attach_command == "controlkeel attach codex-cli"
    assert codex_app_server.attach_command == codex_cli.attach_command
    assert t3code.attach_command == codex_cli.attach_command

    assert codex_app_server.runtime_transport == "codex_app_server_json_rpc"
    assert t3code.runtime_transport == "t3code_provider_runtime"

    assert direct_installs =~
             "there is still no separate `controlkeel attach codex-app-server` command"

    assert direct_installs =~ "`controlkeel attach codex-cli`"
    assert direct_installs =~ "restart Codex after attach or plugin changes"
    assert direct_installs =~ "trust the repo"

    assert integrations =~
             "`controlkeel attach codex-cli` is still the setup step for both Codex CLI and Codex app-server based clients"

    assert integrations =~
             "Codex only loads project-scoped `.codex/` config and hooks when the project is trusted."

    assert integrations =~
             "Restart Codex after `controlkeel attach codex-cli` or `controlkeel plugin install codex`"
  end

  defp read_doc!(path) do
    @repo_root
    |> Path.join(path)
    |> File.read!()
  end
end
