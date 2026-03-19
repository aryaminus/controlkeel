defmodule ControlKeel.Memory.Record do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Memory.Embedding
  alias ControlKeel.Mission.{Session, Task, Workspace}
  alias ControlKeel.Types.JsonList

  schema "memory_records" do
    field :record_type, :string
    field :title, :string
    field :summary, :string
    field :body, :string, default: ""
    field :tags, JsonList, default: []
    field :source_type, :string
    field :source_id, :string
    field :metadata, :map, default: %{}
    field :archived_at, :utc_datetime

    belongs_to :workspace, Workspace
    belongs_to :session, Session
    belongs_to :task, Task
    has_many :embeddings, Embedding, foreign_key: :memory_record_id

    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :workspace_id,
      :session_id,
      :task_id,
      :record_type,
      :title,
      :summary,
      :body,
      :tags,
      :source_type,
      :source_id,
      :metadata,
      :archived_at
    ])
    |> validate_required([
      :workspace_id,
      :session_id,
      :record_type,
      :title,
      :summary,
      :body,
      :tags,
      :source_type,
      :metadata
    ])
    |> assoc_constraint(:workspace)
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
  end
end
