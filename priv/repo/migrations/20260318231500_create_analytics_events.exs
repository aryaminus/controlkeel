defmodule ControlKeel.Repo.Migrations.CreateAnalyticsEvents do
  use Ecto.Migration

  def change do
    create table(:analytics_events) do
      add :event, :string, null: false
      add :source, :string, null: false
      add :session_id, references(:sessions, on_delete: :delete_all)
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
      add :project_root, :text
      add :metadata, :map, null: false, default: %{}
      add :happened_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:analytics_events, [:event])
    create index(:analytics_events, [:session_id])
    create index(:analytics_events, [:happened_at])
  end
end
