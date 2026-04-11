defmodule ControlKeel.Intent.BoundarySummary do
  @moduledoc false

  alias ControlKeel.Intent.{
    ExecutionBrief,
    ExecutionPosture,
    HarnessPolicy,
    RuntimeRecommendation
  }

  @empty_summary %{
    "risk_tier" => nil,
    "budget_note" => nil,
    "data_summary" => nil,
    "compliance" => [],
    "constraints" => [],
    "open_questions" => [],
    "launch_window" => nil,
    "next_step" => nil,
    "execution_posture" => ExecutionPosture.build(nil),
    "harness_policy" => HarnessPolicy.build(nil),
    "runtime_recommendation" => RuntimeRecommendation.build(nil)
  }

  def build(brief, opts \\ [])

  def build(%ExecutionBrief{} = brief, opts), do: build(ExecutionBrief.to_map(brief), opts)

  def build(brief, opts) when is_map(brief) do
    compiler = nested_map(brief, "compiler")
    answers = nested_map(compiler, "interview_answers")

    %{
      "risk_tier" => optional_string(brief, "risk_tier"),
      "budget_note" => optional_string(brief, "budget_note"),
      "data_summary" => optional_string(brief, "data_summary"),
      "compliance" => normalize_list(Map.get(brief, "compliance") || Map.get(brief, :compliance)),
      "constraints" =>
        normalize_constraints(Map.get(answers, "constraints") || Map.get(answers, :constraints)),
      "open_questions" =>
        normalize_list(Map.get(brief, "open_questions") || Map.get(brief, :open_questions)),
      "launch_window" => optional_string(brief, "launch_window"),
      "next_step" => optional_string(brief, "next_step"),
      "execution_posture" => ExecutionPosture.build(brief),
      "harness_policy" => HarnessPolicy.build(brief),
      "runtime_recommendation" => RuntimeRecommendation.build(brief, opts)
    }
  end

  def build(_brief, _opts), do: @empty_summary

  defp nested_map(map, key) do
    case fetch_key(map, key) do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  defp optional_string(map, key) do
    case fetch_key(map, key) do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end

  defp normalize_constraints(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_constraints(value), do: normalize_list(value)

  defp normalize_list(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_list(value) when is_binary(value), do: normalize_constraints(value)
  defp normalize_list(_value), do: []

  defp fetch_key(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, known_atom_key(key))
  end

  defp known_atom_key("compiler"), do: :compiler
  defp known_atom_key("risk_tier"), do: :risk_tier
  defp known_atom_key("budget_note"), do: :budget_note
  defp known_atom_key("data_summary"), do: :data_summary
  defp known_atom_key("compliance"), do: :compliance
  defp known_atom_key("open_questions"), do: :open_questions
  defp known_atom_key("launch_window"), do: :launch_window
  defp known_atom_key("next_step"), do: :next_step
  defp known_atom_key("interview_answers"), do: :interview_answers
  defp known_atom_key("constraints"), do: :constraints
  defp known_atom_key(_key), do: nil
end
