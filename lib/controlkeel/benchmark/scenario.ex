defmodule ControlKeel.Benchmark.Scenario do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Benchmark.{Result, Suite}
  alias ControlKeel.Types.JsonList

  schema "benchmark_scenarios" do
    field :slug, :string
    field :name, :string
    field :category, :string
    field :incident_label, :string
    field :path, :string
    field :kind, :string, default: "code"
    field :content, :string
    field :expected_rules, JsonList, default: []
    field :expected_decision, :string
    field :position, :integer, default: 0
    field :split, :string, default: "public"
    field :metadata, :map, default: %{}

    belongs_to :suite, Suite
    has_many :results, Result

    timestamps(type: :utc_datetime)
  end

  def changeset(scenario, attrs) do
    scenario
    |> cast(attrs, [
      :suite_id,
      :slug,
      :name,
      :category,
      :incident_label,
      :path,
      :kind,
      :content,
      :expected_rules,
      :expected_decision,
      :position,
      :split,
      :metadata
    ])
    |> validate_required([
      :suite_id,
      :slug,
      :name,
      :category,
      :kind,
      :content,
      :expected_rules,
      :position,
      :split,
      :metadata
    ])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:suite_id, :slug])
    |> assoc_constraint(:suite)
  end
end
