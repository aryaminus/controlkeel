defmodule ControlKeel.Intent.ExecutionBrief do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @schema_version 1
  @risk_tiers ~w(moderate high critical)
  @domain_packs ~w(software healthcare education)
  @required_provider_fields ~w(
    objective
    users
    occupation
    domain_pack
    risk_tier
    data_summary
    compliance
    recommended_stack
    acceptance_criteria
    open_questions
    estimated_tasks
    budget_note
    next_step
  )

  embedded_schema do
    field :project_name, :string
    field :idea, :string
    field :objective, :string
    field :users, :string
    field :occupation, :string
    field :domain_pack, :string
    field :risk_tier, :string
    field :data_summary, :string
    field :recommended_stack, :string
    field :budget_note, :string
    field :next_step, :string
    field :launch_window, :string
    field :success_signal, :string
    field :estimated_tasks, :integer
    field :compliance, {:array, :string}, default: []
    field :acceptance_criteria, {:array, :string}, default: []
    field :open_questions, {:array, :string}, default: []
    field :key_features, {:array, :string}, default: []
    field :compiler, :map, default: %{}
  end

  def provider_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => @required_provider_fields,
      "properties" => %{
        "project_name" => string_schema(80),
        "idea" => string_schema(600),
        "objective" => string_schema(600),
        "users" => string_schema(400),
        "occupation" => string_schema(120),
        "domain_pack" => %{"type" => "string", "enum" => @domain_packs},
        "risk_tier" => %{"type" => "string", "enum" => @risk_tiers},
        "data_summary" => string_schema(600),
        "recommended_stack" => string_schema(600),
        "budget_note" => string_schema(240),
        "next_step" => string_schema(400),
        "launch_window" => string_schema(240),
        "success_signal" => string_schema(240),
        "estimated_tasks" => %{"type" => "integer", "minimum" => 1, "maximum" => 25},
        "compliance" => array_schema(6),
        "acceptance_criteria" => array_schema(6),
        "open_questions" => array_schema(5),
        "key_features" => array_schema(6)
      }
    }
  end

  def from_provider_response(attrs, compiler_metadata)
      when is_map(attrs) and is_map(compiler_metadata) do
    attrs
    |> normalize_provider_map()
    |> Map.put("compiler", compiler_metadata)
    |> then(&changeset(%__MODULE__{}, &1))
    |> case do
      %Ecto.Changeset{valid?: true} = changeset -> {:ok, apply_changes(changeset)}
      changeset -> {:error, changeset}
    end
  end

  def to_map(%__MODULE__{} = brief) do
    brief
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  def schema_version, do: @schema_version

  def changeset(brief, attrs) do
    brief
    |> cast(attrs, [
      :project_name,
      :idea,
      :objective,
      :users,
      :occupation,
      :domain_pack,
      :risk_tier,
      :data_summary,
      :recommended_stack,
      :budget_note,
      :next_step,
      :launch_window,
      :success_signal,
      :estimated_tasks,
      :compliance,
      :acceptance_criteria,
      :open_questions,
      :key_features,
      :compiler
    ])
    |> validate_required([
      :objective,
      :users,
      :occupation,
      :domain_pack,
      :risk_tier,
      :data_summary,
      :recommended_stack,
      :budget_note,
      :next_step,
      :estimated_tasks,
      :compliance,
      :acceptance_criteria,
      :open_questions,
      :compiler
    ])
    |> validate_inclusion(:domain_pack, @domain_packs)
    |> validate_inclusion(:risk_tier, @risk_tiers)
    |> validate_number(:estimated_tasks, greater_than: 0, less_than_or_equal_to: 25)
    |> validate_list(:compliance)
    |> validate_list(:acceptance_criteria)
    |> validate_list(:open_questions)
    |> validate_list(:key_features, allow_empty: true)
    |> validate_compiler_metadata()
  end

  defp validate_list(changeset, field, opts \\ []) do
    allow_empty = Keyword.get(opts, :allow_empty, false)

    validate_change(changeset, field, fn ^field, value ->
      cond do
        not is_list(value) ->
          [{field, "must be a list of short strings"}]

        value == [] and not allow_empty ->
          [{field, "must include at least one item"}]

        Enum.any?(value, &(not is_binary(&1) or String.trim(&1) == "")) ->
          [{field, "must include only non-empty strings"}]

        true ->
          []
      end
    end)
  end

  defp validate_compiler_metadata(changeset) do
    validate_change(changeset, :compiler, fn :compiler, value ->
      required =
        ~w(provider model schema_version fallback_chain occupation domain_pack interview_answers)

      cond do
        not is_map(value) ->
          [compiler: "must be a metadata map"]

        Enum.any?(required, &(Map.get(value, &1) in [nil, ""])) ->
          [compiler: "is missing required metadata"]

        not is_list(value["fallback_chain"]) ->
          [compiler: "must include a provider fallback chain"]

        not is_map(value["interview_answers"]) ->
          [compiler: "must include normalized interview answers"]

        true ->
          []
      end
    end)
  end

  defp normalize_provider_map(attrs) do
    attrs
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), normalize_value(value)} end)
    |> Map.update("compliance", [], &normalize_list/1)
    |> Map.update("acceptance_criteria", [], &normalize_list/1)
    |> Map.update("open_questions", [], &normalize_list/1)
    |> Map.update("key_features", [], &normalize_list/1)
    |> Map.update("estimated_tasks", 1, &normalize_integer/1)
  end

  defp normalize_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)

  defp normalize_value(value) when is_map(value) do
    Enum.into(value, %{}, fn {key, nested} -> {to_string(key), normalize_value(nested)} end)
  end

  defp normalize_value(value), do: value

  defp normalize_list(value) when is_list(value) do
    value
    |> Enum.map(&to_string(&1))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_list(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,]/, trim: true)
    |> normalize_list()
  end

  defp normalize_list(_value), do: []

  defp normalize_integer(value) when is_integer(value), do: max(value, 1)

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> max(parsed, 1)
      _ -> 1
    end
  end

  defp normalize_integer(_value), do: 1

  defp string_schema(max_length) do
    %{"type" => "string", "minLength" => 3, "maxLength" => max_length}
  end

  defp array_schema(max_items) do
    %{
      "type" => "array",
      "minItems" => 1,
      "maxItems" => max_items,
      "items" => %{"type" => "string", "minLength" => 3, "maxLength" => 240}
    }
  end
end
