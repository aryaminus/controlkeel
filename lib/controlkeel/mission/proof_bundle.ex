defmodule ControlKeel.Mission.ProofBundle do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Session, Task}

  schema "proof_bundles" do
    field :version, :integer
    field :status, :string
    field :risk_score, :float, default: 0.0
    field :deploy_ready, :boolean, default: false
    field :open_findings_count, :integer, default: 0
    field :blocked_findings_count, :integer, default: 0
    field :approved_findings_count, :integer, default: 0
    field :bundle, :map, default: %{}
    field :generated_at, :utc_datetime

    belongs_to :session, Session
    belongs_to :task, Task

    timestamps(type: :utc_datetime)
  end

  def changeset(proof_bundle, attrs) do
    proof_bundle
    |> cast(attrs, [
      :session_id,
      :task_id,
      :version,
      :status,
      :risk_score,
      :deploy_ready,
      :open_findings_count,
      :blocked_findings_count,
      :approved_findings_count,
      :bundle,
      :generated_at
    ])
    |> validate_required([
      :session_id,
      :task_id,
      :version,
      :status,
      :risk_score,
      :deploy_ready,
      :open_findings_count,
      :blocked_findings_count,
      :approved_findings_count,
      :bundle,
      :generated_at
    ])
    |> validate_number(:version, greater_than: 0)
    |> validate_number(:open_findings_count, greater_than_or_equal_to: 0)
    |> validate_number(:blocked_findings_count, greater_than_or_equal_to: 0)
    |> validate_number(:approved_findings_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:task_id, :version])
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
  end
end
