defmodule ControlKeel.Repo.Migrations.AddPolicyTrainingPipeline do
  use Ecto.Migration

  def change do
    create table(:policy_training_runs) do
      add :artifact_type, :string, null: false
      add :status, :string, null: false, default: "queued"
      add :training_scope, :string, null: false
      add :dataset_summary, :map, null: false, default: %{}
      add :training_metrics, :map, null: false, default: %{}
      add :validation_metrics, :map, null: false, default: %{}
      add :held_out_metrics, :map, null: false, default: %{}
      add :failure_reason, :text
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:policy_training_runs, [:artifact_type])
    create index(:policy_training_runs, [:status])
    create index(:policy_training_runs, [:started_at])

    create table(:policy_artifacts) do
      add :training_run_id, references(:policy_training_runs, on_delete: :delete_all), null: false
      add :artifact_type, :string, null: false
      add :version, :integer, null: false
      add :status, :string, null: false, default: "candidate"
      add :model_family, :string, null: false
      add :artifact, :map, null: false, default: %{}
      add :feature_spec, :map, null: false, default: %{}
      add :metrics, :map, null: false, default: %{}
      add :activated_at, :utc_datetime
      add :archived_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:policy_artifacts, [:artifact_type, :version])
    create index(:policy_artifacts, [:artifact_type])
    create index(:policy_artifacts, [:status])

    create unique_index(:policy_artifacts, [:artifact_type],
             where: "status = 'active'",
             name: :policy_artifacts_one_active_per_type
           )
  end
end
