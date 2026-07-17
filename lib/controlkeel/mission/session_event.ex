defmodule ControlKeel.Mission.SessionEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Cloud.Telemetry.Envelope
  alias ControlKeel.Mission.{Finding, Review, Session, Task}

  schema "session_events" do
    field :event_type, :string
    field :actor, :string
    field :summary, :string
    field :body, :string, default: ""
    field :payload, :map, default: %{}
    field :metadata, :map, default: %{}
    field :external_id, :string
    field :synced_at, :utc_datetime

    belongs_to :session, Session
    belongs_to :task, Task
    belongs_to :review, Review
    belongs_to :finding, Finding

    timestamps(type: :utc_datetime)
  end

  @external_id_prefix "se_"

  def changeset(session_event, attrs) do
    session_event
    |> cast(attrs, [
      :event_type,
      :actor,
      :summary,
      :body,
      :payload,
      :metadata,
      :external_id,
      :synced_at,
      :review_id,
      :finding_id,
      :session_id,
      :task_id
    ])
    |> validate_required([
      :event_type,
      :actor,
      :summary,
      :payload,
      :metadata,
      :session_id
    ])
    |> maybe_generate_external_id()
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
    |> assoc_constraint(:review)
    |> assoc_constraint(:finding)
    |> unique_constraint(:external_id)
  end

  @doc """
  Allowlist of fields safe to ship via cloud sync. `body`, `payload`, and
  `metadata` pass through the redactor because they can contain log lines,
  tool output, or user-pasted content.
  """
  def sync_fields do
    {:include,
     [
       :id,
       :external_id,
       :session_id,
       :task_id,
       :event_type,
       :actor,
       :summary,
       {:redact, :body},
       {:redact, :payload},
       {:redact, :metadata},
       :review_id,
       :finding_id,
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
