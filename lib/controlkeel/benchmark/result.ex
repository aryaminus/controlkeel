defmodule ControlKeel.Benchmark.Result do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Benchmark.{Run, Scenario}

  schema "benchmark_results" do
    field :subject, :string
    field :subject_type, :string
    field :status, :string, default: "pending"
    field :decision, :string
    field :findings_count, :integer, default: 0
    field :matched_expected, :boolean, default: false
    field :latency_ms, :integer
    field :overhead_percent, :float
    field :payload, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :run, Run
    belongs_to :scenario, Scenario

    timestamps(type: :utc_datetime)
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [
      :run_id,
      :scenario_id,
      :subject,
      :subject_type,
      :status,
      :decision,
      :findings_count,
      :matched_expected,
      :latency_ms,
      :overhead_percent,
      :payload,
      :metadata
    ])
    |> validate_required([
      :run_id,
      :scenario_id,
      :subject,
      :subject_type,
      :status,
      :findings_count,
      :matched_expected,
      :payload,
      :metadata
    ])
    |> validate_number(:findings_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:run_id, :scenario_id, :subject])
    |> assoc_constraint(:run)
    |> assoc_constraint(:scenario)
  end
end
