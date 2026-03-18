defmodule ControlKeel.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:workspaces) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :industry, :string, null: false
      add :agent, :string, null: false
      add :budget_cents, :integer, null: false, default: 0
      add :compliance_profile, :string, null: false
      add :status, :string, null: false, default: "draft"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspaces, [:slug])
    create index(:workspaces, [:industry])
    create index(:workspaces, [:agent])
  end
end
