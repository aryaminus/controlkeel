defmodule ControlKeel.Repo.Migrations.CreateSessionEvents do
  use Ecto.Migration

  def change do
    create table(:session_events) do
      add :event_type, :string, null: false
      add :actor, :string, null: false
      add :summary, :string, null: false
      add :body, :text, null: false, default: ""
      add :payload, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:session_events, [:session_id, :inserted_at])
    create index(:session_events, [:task_id, :inserted_at])
    create index(:session_events, [:session_id, :event_type])
  end
end
