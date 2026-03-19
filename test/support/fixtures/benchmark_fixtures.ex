defmodule ControlKeel.BenchmarkFixtures do
  @moduledoc false

  alias ControlKeel.Benchmark

  def benchmark_suite_fixture(slug \\ "vibe_failures_v1") do
    Benchmark.get_suite_by_slug(slug)
  end

  def benchmark_run_fixture(attrs \\ %{}, project_root \\ File.cwd!()) do
    attrs =
      attrs
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
      |> Enum.into(%{
        "suite" => "vibe_failures_v1",
        "subjects" => "controlkeel_validate",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hardcoded_api_key_python_webhook"
      })

    {:ok, run} = Benchmark.run_suite(attrs, project_root)
    run
  end

  def write_benchmark_subjects!(project_root, subjects) when is_list(subjects) do
    path = Path.join(Path.expand(project_root), "controlkeel/benchmark_subjects.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"subjects" => subjects}, pretty: true))
    path
  end
end
