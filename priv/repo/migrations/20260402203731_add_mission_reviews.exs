defmodule ControlKeel.Repo.Migrations.AddMissionReviews do
  use Ecto.Migration

  def change do
    create table(:reviews) do
      add :title, :string, null: false
      add :review_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :submission_body, :text, null: false
      add :annotations, :map, null: false, default: %{}
      add :feedback_notes, :text
      add :submitted_by, :string
      add :reviewed_by, :string
      add :metadata, :map, null: false, default: %{}
      add :responded_at, :utc_datetime
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :nilify_all)
      add :previous_review_id, references(:reviews, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:reviews, [:session_id])
    create index(:reviews, [:task_id])
    create index(:reviews, [:previous_review_id])
    create index(:reviews, [:task_id, :review_type, :inserted_at])
    create index(:reviews, [:session_id, :review_type, :inserted_at])
  end
end
