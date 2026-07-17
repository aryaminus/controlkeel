defmodule ControlKeel.Mission.Finding do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Cloud.Telemetry.Envelope
  alias ControlKeel.Mission.{Finding, Session}

  schema "findings" do
    field :external_id, :string
    field :title, :string
    field :severity, :string
    field :category, :string
    field :rule_id, :string
    field :plain_message, :string
    field :status, :string, default: "open"
    field :auto_resolved, :boolean, default: false
    field :metadata, :map, default: %{}
    field :synced_at, :utc_datetime

    belongs_to :session, Session
    belongs_to :extends_finding, Finding
    belongs_to :contradicts_finding, Finding

    timestamps(type: :utc_datetime)
  end

  @external_id_prefix "f_"

  def changeset(finding, attrs) do
    finding
    |> cast(attrs, [
      :external_id,
      :title,
      :severity,
      :category,
      :rule_id,
      :plain_message,
      :status,
      :auto_resolved,
      :metadata,
      :synced_at,
      :session_id,
      :extends_finding_id,
      :contradicts_finding_id
    ])
    |> validate_required([
      :title,
      :severity,
      :category,
      :rule_id,
      :plain_message,
      :status,
      :auto_resolved,
      :metadata,
      :session_id
    ])
    |> maybe_generate_external_id()
    |> unique_constraint(:external_id)
    |> assoc_constraint(:session)
    |> assoc_constraint(:extends_finding)
    |> assoc_constraint(:contradicts_finding)
  end

  @doc """
  Allowlist of fields safe to ship via cloud sync. `plain_message` and `metadata`
  are passed through `Cloud.Redactor.redact_value/1` because finding messages
  occasionally carry stack-frames with embedded tokens.
  """
  def sync_fields do
    {:include,
     [
       :id,
       :external_id,
       :session_id,
       :title,
       :severity,
       :category,
       :rule_id,
       {:redact, :plain_message},
       :status,
       :auto_resolved,
       {:redact, :metadata},
       :extends_finding_id,
       :contradicts_finding_id,
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
