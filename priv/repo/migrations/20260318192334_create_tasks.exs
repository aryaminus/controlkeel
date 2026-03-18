defmodule ControlKeel.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :title, :string, null: false
      add :status, :string, null: false, default: "queued"
      add :estimated_cost_cents, :integer, null: false, default: 0
      add :validation_gate, :string, null: false
      add :position, :integer, null: false
      add :metadata, :map, null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:session_id])
    create index(:tasks, [:status])
  end
end
