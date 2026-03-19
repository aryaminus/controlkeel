defmodule ControlKeel.Repo.Migrations.AddTaskConfidence do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :confidence_score, :float, default: nil
      add :rollback_boundary, :string, default: nil
    end
  end
end
