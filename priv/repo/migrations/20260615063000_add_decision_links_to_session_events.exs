defmodule ControlKeel.Repo.Migrations.AddDecisionLinksToSessionEvents do
  use Ecto.Migration

  def change do
    alter table(:session_events) do
      add :review_id, references(:reviews, on_delete: :nilify_all)
      add :finding_id, references(:findings, on_delete: :nilify_all)
    end

    create index(:session_events, [:review_id, :inserted_at])
    create index(:session_events, [:finding_id, :inserted_at])
  end
end
