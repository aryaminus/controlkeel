defmodule ControlKeel.Repo.Migrations.CreateFindingAuditEvents do
  use Ecto.Migration

  def change do
    create table(:finding_audit_events) do
      add :finding_id, references(:findings, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :previous_status, :string, null: false
      add :new_status, :string, null: false
      add :reason, :string
      add :actor_user_id, references(:users, on_delete: :nilify_all)
      add :actor_source, :string
      add :actor_identifier, :string
      add :recorded_at, :utc_datetime, null: false
    end

    create index(:finding_audit_events, [:finding_id, :recorded_at])
    create index(:finding_audit_events, [:event_type, :recorded_at])
  end
end
