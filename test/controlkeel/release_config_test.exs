defmodule ControlKeel.ReleaseConfigTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "project release config includes burrito targets" do
    release = Mix.Project.config()[:releases][:controlkeel]

    assert release[:burrito][:targets] == [
             macos: [os: :darwin, cpu: :x86_64],
             macos_silicon: [os: :darwin, cpu: :aarch64],
             linux: [os: :linux, cpu: :x86_64],
             linux_arm64: [os: :linux, cpu: :aarch64],
             windows: [os: :windows, cpu: :x86_64]
           ]
  end

  test "release-bearing manifests stay version aligned" do
    app_version = Mix.Project.config()[:version]
    npm_package = read_json("packages/npm/controlkeel/package.json")
    npm_server = read_json("packages/npm/controlkeel/server.json")
    root_plugin = read_json("plugin.json")
    cursor_plugin = read_json(".cursor-plugin/plugin.json")

    assert npm_package["version"] == app_version
    assert npm_server["version"] == app_version
    assert root_plugin["version"] == app_version
    assert cursor_plugin["version"] == app_version

    assert Enum.all?(npm_server["packages"], &(&1["version"] == app_version))
  end

  test "npm package publishes MCP registry metadata" do
    npm_package = read_json("packages/npm/controlkeel/package.json")

    assert "server.json" in npm_package["files"]
  end

  test "cursor plugin manifest declares well-formed relative resource paths" do
    manifest = read_json(".cursor-plugin/plugin.json")

    for key <- ~w(agents commands hooks rules skills) do
      path = Map.fetch!(manifest, key)

      assert String.starts_with?(path, "./"),
             "expected #{key} to be a relative ./ path, got: #{inspect(path)}"

      relative = String.trim_leading(path, "./") |> String.trim_trailing("/")

      refute String.starts_with?(relative, "/"),
             "expected #{key} to stay inside the plugin root, got: #{inspect(path)}"

      refute String.starts_with?(relative, ".."),
             "expected #{key} to not escape the plugin root, got: #{inspect(path)}"
    end
  end

  test "cursor plugin manifest matches the canonical exporter output" do
    manifest = read_json(".cursor-plugin/plugin.json")

    generated =
      ControlKeel.Skills.Exporter.cursor_plugin_manifest(@root, version: manifest["version"])

    assert manifest["name"] == generated["name"]
    assert manifest["description"] == generated["description"]
    assert manifest["rules"] == generated["rules"]
    assert manifest["skills"] == generated["skills"]
    assert manifest["agents"] == generated["agents"]
    assert manifest["commands"] == generated["commands"]
    assert manifest["hooks"] == generated["hooks"]

    assert get_in(manifest, ["mcpServers", "controlkeel", "command"]) ==
             get_in(generated, ["mcpServers", "controlkeel", "command"])

    assert get_in(manifest, ["mcpServers", "controlkeel", "args"]) ==
             get_in(generated, ["mcpServers", "controlkeel", "args"])
  end

  defp read_json(relative_path) do
    @root
    |> Path.join(relative_path)
    |> File.read!()
    |> Jason.decode!()
  end
end
