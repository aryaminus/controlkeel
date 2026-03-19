defmodule ControlKeel.Benchmark.Suite do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Benchmark.{Run, Scenario}

  schema "benchmark_suites" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :version, :integer, default: 1
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    has_many :scenarios, Scenario
    has_many :runs, Run

    timestamps(type: :utc_datetime)
  end

  def changeset(suite, attrs) do
    suite
    |> cast(attrs, [:slug, :name, :description, :version, :status, :metadata])
    |> validate_required([:slug, :name, :description, :version, :status, :metadata])
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint(:slug)
  end
end
