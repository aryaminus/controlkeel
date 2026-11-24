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
    field :last_run_at, :utc_datetime

    has_many :scenarios, Scenario
    has_many :runs, Run
    belongs_to :workspace, ControlKeel.Mission.Workspace

    timestamps(type: :utc_datetime)
  end

  def changeset(suite, attrs) do
    suite
    |> cast(attrs, [
      :slug,
      :name,
      :description,
      :version,
      :status,
      :metadata,
      :last_run_at,
      :workspace_id
    ])
    |> validate_required([:slug, :name, :description, :version, :status, :metadata])
    |> validate_number(:version, greater_than: 0)
    # Skipped when workspace_id is nil (built-in platform suites).
    |> assoc_constraint(:workspace)
    # Slug uniqueness is scoped per workspace (NULL = platform content); see
    # the scope_benchmark_suite_slugs_by_workspace migration.
    |> unique_constraint([:workspace_id, :slug])
  end
end
