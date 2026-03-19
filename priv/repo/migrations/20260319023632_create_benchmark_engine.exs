defmodule ControlKeel.Repo.Migrations.CreateBenchmarkEngine do
  use Ecto.Migration

  def change do
    create table(:benchmark_suites) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :string, null: false
      add :version, :integer, null: false, default: 1
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:benchmark_suites, [:slug])

    create table(:benchmark_scenarios) do
      add :suite_id, references(:benchmark_suites, on_delete: :delete_all), null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :category, :string, null: false
      add :incident_label, :string
      add :path, :string
      add :kind, :string, null: false, default: "code"
      add :content, :string, null: false
      add :expected_rules, :string, null: false, default: "[]"
      add :expected_decision, :string
      add :position, :integer, null: false, default: 0
      add :split, :string, null: false, default: "public"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:benchmark_scenarios, [:suite_id, :slug])
    create index(:benchmark_scenarios, [:suite_id, :position])
    create index(:benchmark_scenarios, [:split])

    create table(:benchmark_runs) do
      add :suite_id, references(:benchmark_suites, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :baseline_subject, :string, null: false
      add :subjects, :string, null: false, default: "[]"
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      add :total_scenarios, :integer, null: false, default: 0
      add :caught_count, :integer, null: false, default: 0
      add :blocked_count, :integer, null: false, default: 0
      add :catch_rate, :float, null: false, default: 0.0
      add :median_latency_ms, :integer
      add :average_overhead_percent, :float
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:benchmark_runs, [:suite_id])
    create index(:benchmark_runs, [:status])
    create index(:benchmark_runs, [:started_at])

    create table(:benchmark_results) do
      add :run_id, references(:benchmark_runs, on_delete: :delete_all), null: false
      add :scenario_id, references(:benchmark_scenarios, on_delete: :delete_all), null: false
      add :subject, :string, null: false
      add :subject_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :decision, :string
      add :findings_count, :integer, null: false, default: 0
      add :matched_expected, :boolean, null: false, default: false
      add :latency_ms, :integer
      add :overhead_percent, :float
      add :payload, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:benchmark_results, [:run_id, :scenario_id, :subject])
    create index(:benchmark_results, [:run_id])
    create index(:benchmark_results, [:scenario_id])
    create index(:benchmark_results, [:subject])
    create index(:benchmark_results, [:status])
  end
end
