defmodule ControlKeel.CodexConfigTest do
  use ExUnit.Case, async: true

  alias ControlKeel.CodexConfig

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-codex-config-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "writes and updates a managed codex block without clobbering other config", %{
    tmp_dir: tmp_dir
  } do
    config_path = Path.join(tmp_dir, ".codex/config.toml")

    File.mkdir_p!(Path.dirname(config_path))

    File.write!(
      config_path,
      """
      model = "gpt-5.4"

      [features]
      multi_agent = true
      """
    )

    assert {:ok, ^config_path} =
             CodexConfig.write(config_path, %{
               command: "controlkeel",
               args: ["mcp", "--project-root", "/repo/one"]
             })

    first_write = File.read!(config_path)
    assert first_write =~ ~s(model = "gpt-5.4")
    assert first_write =~ "[features]"
    assert first_write =~ "multi_agent = true"
    assert first_write =~ "codex_hooks = true"
    assert first_write =~ "[mcp_servers.controlkeel]"
    assert first_write =~ ~s(args = ["mcp", "--project-root", "/repo/one"])
    assert first_write =~ ~s(config_file = "./agents/controlkeel-operator.toml")

    assert {:ok, ^config_path} =
             CodexConfig.write(config_path, %{
               command: "controlkeel",
               args: ["mcp", "--project-root", "/repo/two"]
             })

    second_write = File.read!(config_path)
    assert second_write =~ ~s(model = "gpt-5.4")
    assert second_write =~ "codex_hooks = true"
    assert second_write =~ ~s(args = ["mcp", "--project-root", "/repo/two"])
    refute second_write =~ ~s(args = ["mcp", "--project-root", "/repo/one"])
    assert length(String.split(second_write, "[mcp_servers.controlkeel]")) == 2
  end
end
