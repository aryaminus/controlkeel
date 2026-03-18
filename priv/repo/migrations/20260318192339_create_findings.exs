defmodule ControlKeel.Repo.Migrations.CreateFindings do
  use Ecto.Migration

  def change do
    create table(:findings) do
      add :title, :string, null: false
      add :severity, :string, null: false
      add :category, :string, null: false
      add :rule_id, :string, null: false
      add :plain_message, :text, null: false
      add :status, :string, null: false, default: "open"
      add :auto_resolved, :boolean, default: false, null: false
      add :metadata, :map, null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:findings, [:session_id])
    create index(:findings, [:severity])
    create index(:findings, [:status])
  end
end
