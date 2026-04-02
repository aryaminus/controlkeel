defmodule ControlKeel.Repo.Migrations.AddSessionMetadataAndRuntimeContext do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :metadata, :map, null: false, default: %{}
    end
  end
end
