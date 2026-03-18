defmodule ControlKeel.Mission.Invocation do
  use Ecto.Schema
  import Ecto.Changeset

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

    belongs_to :session, Session
    belongs_to :task, Task

    timestamps(type: :utc_datetime)
  end

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
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
  end
end
