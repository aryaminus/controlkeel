defmodule ControlKeel.Mission.Review do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Review, Session, Task}

  @review_types ~w(plan diff completion)
  @review_statuses ~w(pending approved denied superseded)

  schema "reviews" do
    field :title, :string
    field :review_type, :string
    field :status, :string, default: "pending"
    field :submission_body, :string
    field :annotations, :map, default: %{}
    field :feedback_notes, :string
    field :submitted_by, :string
    field :reviewed_by, :string
    field :metadata, :map, default: %{}
    field :responded_at, :utc_datetime

    belongs_to :session, Session
    belongs_to :task, Task
    belongs_to :previous_review, Review
    has_many :revisions, Review, foreign_key: :previous_review_id

    timestamps(type: :utc_datetime)
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [
      :title,
      :review_type,
      :status,
      :submission_body,
      :annotations,
      :feedback_notes,
      :submitted_by,
      :reviewed_by,
      :metadata,
      :responded_at,
      :session_id,
      :task_id,
      :previous_review_id
    ])
    |> validate_required([:title, :review_type, :status, :submission_body, :session_id])
    |> validate_inclusion(:review_type, @review_types)
    |> validate_inclusion(:status, @review_statuses)
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
    |> assoc_constraint(:previous_review)
  end
end
