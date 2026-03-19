defmodule ControlKeel.Repo.Migrations.AddProofAndMemoryLayers do
  use Ecto.Migration

  def up do
    create table(:proof_bundles) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :status, :string, null: false
      add :risk_score, :float, null: false, default: 0.0
      add :deploy_ready, :boolean, null: false, default: false
      add :open_findings_count, :integer, null: false, default: 0
      add :blocked_findings_count, :integer, null: false, default: 0
      add :approved_findings_count, :integer, null: false, default: 0
      add :bundle, :map, null: false, default: %{}
      add :generated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:proof_bundles, [:task_id, :version])
    create index(:proof_bundles, [:session_id])
    create index(:proof_bundles, [:task_id])
    create index(:proof_bundles, [:generated_at])

    create table(:memory_records) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :nilify_all)
      add :record_type, :string, null: false
      add :title, :string, null: false
      add :summary, :string, null: false
      add :body, :string, null: false, default: ""
      add :tags, :string, null: false, default: "[]"
      add :source_type, :string, null: false
      add :source_id, :string
      add :metadata, :map, null: false, default: %{}
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:memory_records, [:workspace_id])
    create index(:memory_records, [:session_id])
    create index(:memory_records, [:task_id])
    create index(:memory_records, [:record_type])
    create index(:memory_records, [:archived_at])

    create table(:memory_embeddings) do
      add :memory_record_id, references(:memory_records, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :model, :string, null: false
      add :dimensions, :integer, null: false
      add :embedding_text, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:memory_embeddings, [:memory_record_id, :provider, :model])
    create index(:memory_embeddings, [:provider, :model])

    create table(:task_checkpoints) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :checkpoint_type, :string, null: false
      add :summary, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :created_by, :string, null: false, default: "system"

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:task_checkpoints, [:session_id])
    create index(:task_checkpoints, [:task_id])
    create index(:task_checkpoints, [:checkpoint_type])

    if sqlite_repo?() do
      execute("""
      CREATE VIRTUAL TABLE memory_records_fts
      USING fts5(memory_record_id UNINDEXED, document)
      """)

      execute("""
      CREATE TRIGGER memory_records_ai AFTER INSERT ON memory_records BEGIN
        INSERT INTO memory_records_fts(memory_record_id, document)
        VALUES (
          new.id,
          trim(
            coalesce(new.title, '') || ' ' ||
            coalesce(new.summary, '') || ' ' ||
            coalesce(new.body, '') || ' ' ||
            coalesce(json_extract(new.tags, '$'), '')
          )
        );
      END;
      """)

      execute("""
      CREATE TRIGGER memory_records_ad AFTER DELETE ON memory_records BEGIN
        DELETE FROM memory_records_fts WHERE memory_record_id = old.id;
      END;
      """)

      execute("""
      CREATE TRIGGER memory_records_au AFTER UPDATE ON memory_records BEGIN
        DELETE FROM memory_records_fts WHERE memory_record_id = old.id;
        INSERT INTO memory_records_fts(memory_record_id, document)
        VALUES (
          new.id,
          trim(
            coalesce(new.title, '') || ' ' ||
            coalesce(new.summary, '') || ' ' ||
            coalesce(new.body, '') || ' ' ||
            coalesce(json_extract(new.tags, '$'), '')
          )
        );
      END;
      """)
    end
  end

  def down do
    if sqlite_repo?() do
      execute("DROP TRIGGER IF EXISTS memory_records_au")
      execute("DROP TRIGGER IF EXISTS memory_records_ad")
      execute("DROP TRIGGER IF EXISTS memory_records_ai")
      execute("DROP TABLE IF EXISTS memory_records_fts")
    end

    drop table(:task_checkpoints)
    drop table(:memory_embeddings)
    drop table(:memory_records)
    drop table(:proof_bundles)
  end

  defp sqlite_repo? do
    repo().__adapter__() == Ecto.Adapters.SQLite3
  end
end
