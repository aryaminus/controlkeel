defmodule ControlKeel.Platform.ServiceAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Platform.TaskRun

  schema "service_accounts" do
    field :name, :string
    field :token_hash, :string
    field :scopes, :map, default: %{"values" => []}
    field :status, :string, default: "active"
    field :last_used_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :workspace, Workspace
    has_many :task_runs, TaskRun

    timestamps(type: :utc_datetime)
  end

  def changeset(service_account, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> normalize_scopes()

    service_account
    |> cast(attrs, [:workspace_id, :name, :token_hash, :scopes, :status, :last_used_at, :metadata])
    |> validate_required([:workspace_id, :name, :token_hash, :scopes, :status, :metadata])
    |> validate_inclusion(:status, ["active", "revoked", "disabled"])
    |> assoc_constraint(:workspace)
    |> unique_constraint(:token_hash)
  end

  def scope_list(%__MODULE__{scopes: %{"values" => values}}) when is_list(values), do: values
  def scope_list(%__MODULE__{scopes: _}), do: []

  def active?(%__MODULE__{status: "active"}), do: true
  def active?(%__MODULE__{}), do: false

  defp normalize_scopes(attrs) when is_map(attrs) do
    case Map.get(attrs, "scopes") do
      nil ->
        attrs

      value ->
        scopes =
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

        Map.put(attrs, "scopes", %{"values" => scopes})
    end
  end

  defp stringify_keys(attrs) when is_map(attrs) do
    Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)
  end
end
