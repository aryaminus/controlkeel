defmodule ControlKeel.Platform.AuditExport do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Session

  schema "audit_exports" do
    field :format, :string
    field :status, :string, default: "generated"
    field :checksum, :string
    field :artifact_path_or_ref, :string
    field :generated_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :session, Session

    timestamps(type: :utc_datetime)
  end

  def changeset(audit_export, attrs) do
    audit_export
    |> cast(attrs, [
      :session_id,
      :format,
      :status,
      :checksum,
      :artifact_path_or_ref,
      :generated_at,
      :metadata
    ])
    |> validate_required([:session_id, :format, :status, :metadata])
    |> validate_inclusion(:format, ["json", "csv", "pdf"])
    |> validate_inclusion(:status, ["generated", "failed"])
    |> assoc_constraint(:session)
  end
end
