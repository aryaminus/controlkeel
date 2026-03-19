defmodule ControlKeel.Benchmark.Run do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Benchmark.{Result, Suite}
  alias ControlKeel.Types.JsonList

  schema "benchmark_runs" do
    field :status, :string, default: "pending"
    field :baseline_subject, :string
    field :subjects, JsonList, default: []
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :total_scenarios, :integer, default: 0
    field :caught_count, :integer, default: 0
    field :blocked_count, :integer, default: 0
    field :catch_rate, :float, default: 0.0
    field :median_latency_ms, :integer
    field :average_overhead_percent, :float
    field :metadata, :map, default: %{}

    belongs_to :suite, Suite
    has_many :results, Result

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :suite_id,
      :status,
      :baseline_subject,
      :subjects,
      :started_at,
      :finished_at,
      :total_scenarios,
      :caught_count,
      :blocked_count,
      :catch_rate,
      :median_latency_ms,
      :average_overhead_percent,
      :metadata
    ])
    |> validate_required([
      :suite_id,
      :status,
      :baseline_subject,
      :subjects,
      :started_at,
      :total_scenarios,
      :caught_count,
      :blocked_count,
      :catch_rate,
      :metadata
    ])
    |> validate_number(:total_scenarios, greater_than_or_equal_to: 0)
    |> validate_number(:caught_count, greater_than_or_equal_to: 0)
    |> validate_number(:blocked_count, greater_than_or_equal_to: 0)
    |> assoc_constraint(:suite)
  end
end
