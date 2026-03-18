defmodule ControlKeel.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions) do
      add :title, :string, null: false
      add :objective, :text, null: false
      add :risk_tier, :string, null: false
      add :status, :string, null: false, default: "planned"
      add :budget_cents, :integer, null: false, default: 0
      add :spent_cents, :integer, null: false, default: 0
      add :execution_brief, :map, null: false
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sessions, [:workspace_id])
    create index(:sessions, [:status])
    create index(:sessions, [:risk_tier])
  end
end
