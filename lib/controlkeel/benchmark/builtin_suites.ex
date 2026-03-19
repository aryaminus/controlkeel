defmodule ControlKeel.Benchmark.BuiltinSuites do
  @moduledoc false

  def list do
    benchmark_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(&Path.rootname/1)
    |> Enum.sort()
  end

  def load(slug) when is_binary(slug) do
    path = Path.join(benchmark_dir(), "#{slug}.json")

    with true <- File.exists?(path) || {:error, :not_found},
         {:ok, contents} <- File.read(path),
         {:ok, payload} <- Jason.decode(contents) do
      {:ok, payload}
    else
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp benchmark_dir do
    Application.app_dir(:controlkeel, "priv/benchmarks")
  end
end
