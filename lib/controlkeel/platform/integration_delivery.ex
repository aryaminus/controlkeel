defmodule ControlKeel.Platform.IntegrationDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Platform.IntegrationWebhook

  schema "integration_deliveries" do
    field :event, :string
    field :payload, :map, default: %{}
    field :signature, :string
    field :response_code, :integer
    field :response_body, :string
    field :attempts, :integer, default: 0
    field :status, :string, default: "pending"
    field :last_attempted_at, :utc_datetime
    field :next_retry_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :webhook, IntegrationWebhook
    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :webhook_id,
      :workspace_id,
      :event,
      :payload,
      :signature,
      :response_code,
      :response_body,
      :attempts,
      :status,
      :last_attempted_at,
      :next_retry_at,
      :metadata
    ])
    |> validate_required([
      :webhook_id,
      :workspace_id,
      :event,
      :payload,
      :attempts,
      :status,
      :metadata
    ])
    |> validate_inclusion(:status, ["pending", "delivered", "failed"])
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
    |> assoc_constraint(:webhook)
    |> assoc_constraint(:workspace)
  end
end
