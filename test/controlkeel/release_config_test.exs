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

  defp read_json(relative_path) do
    @root
    |> Path.join(relative_path)
    |> File.read!()
    |> Jason.decode!()
  end
end
