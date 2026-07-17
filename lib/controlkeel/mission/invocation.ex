defmodule ControlKeel.Mission.Invocation do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Cloud.Telemetry.Envelope
  alias ControlKeel.Mission.{Session, Task}

  schema "invocations" do
    field :source, :string
    field :tool, :string
    field :provider, :string
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :cached_input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :estimated_cost_cents, :integer, default: 0
    field :decision, :string
    field :metadata, :map, default: %{}
    field :external_id, :string
    field :synced_at, :utc_datetime

    belongs_to :session, Session
    belongs_to :task, Task

    timestamps(type: :utc_datetime)
  end

  @external_id_prefix "inv_"

  def changeset(invocation, attrs) do
    invocation
    |> cast(attrs, [
      :source,
      :tool,
      :provider,
      :model,
      :input_tokens,
      :cached_input_tokens,
      :output_tokens,
      :estimated_cost_cents,
      :decision,
      :metadata,
      :external_id,
      :synced_at,
      :session_id,
      :task_id
    ])
    |> validate_required([
      :source,
      :tool,
      :estimated_cost_cents,
      :decision,
      :metadata,
      :session_id
    ])
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:cached_input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:estimated_cost_cents, greater_than_or_equal_to: 0)
    |> maybe_generate_external_id()
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
    |> unique_constraint(:external_id)
  end

  @doc """
  Allowlist of fields safe to ship via cloud sync. `metadata` passes through
  the redactor because invocation metadata can carry provider response headers
  or redacted tool arguments.
  """
  def sync_fields do
    {:include,
     [
       :id,
       :external_id,
       :session_id,
       :task_id,
       :source,
       :tool,
       :provider,
       :model,
       :input_tokens,
       :cached_input_tokens,
       :output_tokens,
       :estimated_cost_cents,
       :decision,
       {:redact, :metadata},
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
