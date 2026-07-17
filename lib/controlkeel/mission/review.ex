defmodule ControlKeel.Mission.Review do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.User
  alias ControlKeel.Cloud.Telemetry.Envelope
  alias ControlKeel.Mission.{Review, Session, Task}

  @review_types ~w(plan diff completion)
  @review_statuses ~w(pending approved denied superseded)

  schema "reviews" do
    field :external_id, :string
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
    field :synced_at, :utc_datetime

    field :assigned_at, :utc_datetime
    field :required_role, :string

    belongs_to :session, Session
    belongs_to :task, Task
    belongs_to :previous_review, Review
    belongs_to :assigned_user, User, foreign_key: :assigned_user_id
    belongs_to :assigned_by_user, User, foreign_key: :assigned_by_user_id
    belongs_to :decided_by_user, User, foreign_key: :decided_by_user_id
    has_many :revisions, Review, foreign_key: :previous_review_id

    timestamps(type: :utc_datetime)
  end

  @external_id_prefix "rev_"

  def changeset(review, attrs) do
    review
    |> cast(attrs, [
      :external_id,
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
      :synced_at,
      :session_id,
      :task_id,
      :previous_review_id,
      :assigned_user_id,
      :assigned_by_user_id,
      :assigned_at,
      :decided_by_user_id,
      :required_role
    ])
    |> validate_required([:title, :review_type, :status, :submission_body, :session_id])
    |> validate_inclusion(:review_type, @review_types)
    |> validate_inclusion(:status, @review_statuses)
    |> maybe_generate_external_id()
    |> unique_constraint(:external_id)
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
    |> assoc_constraint(:previous_review)
    |> assoc_constraint(:assigned_user)
    |> assoc_constraint(:assigned_by_user)
    |> assoc_constraint(:decided_by_user)
  end

  @doc """
  Allowlist of fields safe to ship via cloud sync. The submission body and
  feedback notes pass through the redactor because they're free-form text where
  reviewers occasionally paste log lines.
  """
  def sync_fields do
    {:include,
     [
       :id,
       :external_id,
       :session_id,
       :task_id,
       :previous_review_id,
       :title,
       :review_type,
       :status,
       {:redact, :submission_body},
       {:redact, :annotations},
       {:redact, :feedback_notes},
       :submitted_by,
       :reviewed_by,
       {:redact, :metadata},
       :responded_at,
       :assigned_user_id,
       :assigned_by_user_id,
       :assigned_at,
       :decided_by_user_id,
       :required_role,
       :synced_at,
       :inserted_at,
       :updated_at
     ]}
  end

  defp maybe_generate_external_id(changeset) do
    case get_field(changeset, :external_id) do
      nil ->
        put_change(changeset, :external_id, @external_id_prefix <> Envelope.ulid())

      _ ->
        changeset
    end
  end
end
