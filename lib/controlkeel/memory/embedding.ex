defmodule ControlKeel.Memory.Embedding do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Memory.Record
  alias ControlKeel.Types.JsonList

  schema "memory_embeddings" do
    field :provider, :string
    field :model, :string
    field :dimensions, :integer
    field :embedding, JsonList, source: :embedding_text, default: []

    belongs_to :memory_record, Record

    timestamps(type: :utc_datetime)
  end

  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, [:memory_record_id, :provider, :model, :dimensions, :embedding])
    |> validate_required([:memory_record_id, :provider, :model, :dimensions, :embedding])
    |> validate_number(:dimensions, greater_than: 0)
    |> unique_constraint([:memory_record_id, :provider, :model])
    |> assoc_constraint(:memory_record)
  end
end
