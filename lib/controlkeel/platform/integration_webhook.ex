defmodule ControlKeel.Platform.IntegrationWebhook do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Platform.IntegrationDelivery

  schema "integration_webhooks" do
    field :name, :string
    field :url, :string
    field :secret, :string
    field :subscribed_events, :map, default: %{"values" => []}
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :workspace, Workspace
    has_many :deliveries, IntegrationDelivery, foreign_key: :webhook_id

    timestamps(type: :utc_datetime)
  end

  def changeset(webhook, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> normalize_events()

    webhook
    |> cast(attrs, [:workspace_id, :name, :url, :secret, :subscribed_events, :status, :metadata])
    |> validate_required([
      :workspace_id,
      :name,
      :url,
      :secret,
      :subscribed_events,
      :status,
      :metadata
    ])
    |> validate_format(:url, ~r/^https?:\/\//)
    |> validate_inclusion(:status, ["active", "disabled"])
    |> assoc_constraint(:workspace)
  end

  def event_list(%__MODULE__{subscribed_events: %{"values" => values}}) when is_list(values),
    do: values

  def event_list(%__MODULE__{subscribed_events: _}), do: []

  defp normalize_events(attrs) when is_map(attrs) do
    case Map.get(attrs, "subscribed_events") do
      nil ->
        attrs

      value ->
        events =
          value
          |> List.wrap()
          |> Enum.flat_map(fn
            values when is_list(values) -> values
            values when is_binary(values) -> String.split(values, ",", trim: true)
            other -> [other]
          end)
          |> Enum.map(&to_string/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        wrapped = %{"values" => events}
        Map.put(attrs, "subscribed_events", wrapped)
    end
  end

  defp stringify_keys(attrs) when is_map(attrs) do
    Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)
  end
end
