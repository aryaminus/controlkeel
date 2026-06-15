defmodule ControlKeel.Repo.Migrations.AddActorMetadataToReviewAuditEvents do
  use Ecto.Migration

  def change do
    alter table(:review_audit_events) do
      add :actor_source, :string
      add :actor_identifier, :string
    end
  end
end
