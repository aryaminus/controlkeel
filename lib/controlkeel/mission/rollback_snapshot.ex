defmodule ControlKeel.Mission.RollbackSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Finding, Session, Task}

  @valid_statuses ~w(available rolled_back expired unsafe)
  @valid_methods ~w(git_revert git_reset manual)

  schema "rollback_snapshots" do
    field :commit_sha_before, :string
    field :commit_sha_after, :string
    field :status, :string, default: "available"
    field :rollback_method, :string, default: "git_revert"
    field :safety_check, :map, default: %{}
    field :rolled_back_at, :utc_datetime
    field :rolled_back_by, :string
    field :metadata, :map, default: %{}
    field :external_id, :string
    field :synced_at, :utc_datetime

    belongs_to :session, Session
    belongs_to :task, Task
    belongs_to :finding, Finding

    timestamps(type: :utc_datetime)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :session_id,
      :task_id,
      :commit_sha_before,
      :commit_sha_after,
      :status,
      :rollback_method,
      :safety_check,
      :rolled_back_at,
      :rolled_back_by,
      :finding_id,
      :metadata,
      :external_id,
      :synced_at
    ])
    |> validate_required([:session_id, :task_id, :commit_sha_before, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:rollback_method, @valid_methods)
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
    |> unique_constraint(:external_id)
  end
end
