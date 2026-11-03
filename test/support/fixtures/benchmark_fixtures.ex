defmodule ControlKeel.BenchmarkFixtures do
  @moduledoc false

  alias ControlKeel.Benchmark

  @doc """
  The workspace attached to benchmark runs created by these fixtures.
  """
  def benchmark_workspace_id do
    case ControlKeel.Bootstrap.LocalDefaults.ensure() do
      {:ok, {_org, workspace}} when workspace != nil ->
        workspace.id

      _other ->
        ControlKeel.MissionFixtures.workspace_fixture().id
    end
  end

  def benchmark_suite_fixture(slug \\ "vibe_failures_v1") do
    Benchmark.get_suite_by_slug(slug)
  end

  def benchmark_run_fixture(attrs \\ %{}, project_root \\ File.cwd!()) do
    attrs =
      attrs
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
      |> ensure_workspace_id()
      |> Enum.into(%{
        "suite" => "vibe_failures_v1",
        "subjects" => "controlkeel_validate",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hardcoded_api_key_python_webhook"
      })

    {:ok, run} = Benchmark.run_suite(attrs, project_root)
    run
  end

  # Runs are workspace-owned (benchmarks issue, slice 1): a fixture that does
  # not name a workspace attaches to the provisioned default workspace. Tests
  # that model cross-workspace isolation or a specific page's workspace pass
  # "workspace_id" explicitly, and this callback becomes a no-op.
  defp ensure_workspace_id(%{"workspace_id" => _id} = attrs), do: attrs
  defp ensure_workspace_id(attrs), do: Map.put(attrs, "workspace_id", benchmark_workspace_id())

  def write_benchmark_subjects!(project_root, subjects) when is_list(subjects) do
    path = Path.join(Path.expand(project_root), "controlkeel/benchmark_subjects.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"subjects" => subjects}, pretty: true))
    path
  end
end
