defmodule ControlKeel.Mission.TaskCheckpoint do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Cloud.Telemetry.Envelope
  alias ControlKeel.Mission.{Session, Task}

  schema "task_checkpoints" do
    field :checkpoint_type, :string
    field :summary, :string
    field :payload, :map, default: %{}
    field :created_by, :string, default: "system"
    field :external_id, :string
    field :synced_at, :utc_datetime

    belongs_to :session, Session
    belongs_to :task, Task

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @external_id_prefix "tc_"

  def changeset(task_checkpoint, attrs) do
    task_checkpoint
    |> cast(attrs, [
      :session_id,
      :task_id,
      :checkpoint_type,
      :summary,
      :payload,
      :created_by,
      :external_id,
      :synced_at
    ])
    |> validate_required([
      :session_id,
      :task_id,
      :checkpoint_type,
      :summary,
      :payload,
      :created_by
    ])
    |> maybe_generate_external_id()
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
    |> unique_constraint(:external_id)
  end

  @doc """
  Allowlist of fields safe to ship via cloud sync. `payload` passes through
  the redactor because checkpoint payloads can contain file diffs or tool
  output with embedded secrets.
  """
  def sync_fields do
    {:include,
     [
       :id,
       :external_id,
       :session_id,
       :task_id,
       :checkpoint_type,
       :summary,
       {:redact, :payload},
       :created_by,
       :synced_at,
       :inserted_at
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
