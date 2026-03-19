defmodule ControlKeel.Benchmark.Subjects.ControlKeelValidate do
  @moduledoc false

  alias ControlKeel.Benchmark.Runner
  alias ControlKeel.Benchmark.Scenario
  alias ControlKeel.MCP.Tools.CkValidate

  def run(%Scenario{} = scenario, _subject, _opts \\ []) do
    started_at = System.monotonic_time(:millisecond)

    case CkValidate.call(%{
           "content" => scenario.content,
           "path" => scenario.path,
           "kind" => scenario.kind,
           "domain_pack" => get_in(scenario.metadata || %{}, ["domain_pack"])
         }) do
      {:ok, result} ->
        Runner.outcome_from_public_result(
          "completed",
          result,
          System.monotonic_time(:millisecond) - started_at,
          %{"runner" => "controlkeel_validate"}
        )

      {:error, reason} ->
        Runner.error_outcome("failed", reason, System.monotonic_time(:millisecond) - started_at)
    end
  end
end
