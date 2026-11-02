defmodule ControlKeel.Platform.PolicySet do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.Org
  alias ControlKeel.Platform.WorkspacePolicySet
  alias ControlKeel.Utils

  schema "policy_sets" do
    field :name, :string
    field :description, :string
    field :rules, :map, default: %{"entries" => []}
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :org, Org
    has_many :workspace_policy_sets, WorkspacePolicySet

    timestamps(type: :utc_datetime)
  end

  def changeset(policy_set, attrs) do
    attrs =
      attrs
      |> Utils.stringify_keys()
      |> normalize_rules()

    policy_set
    |> cast(attrs, [:org_id, :name, :description, :rules, :status, :metadata])
    |> validate_required([:org_id, :name, :rules, :status, :metadata])
    |> foreign_key_constraint(:org_id)
    |> validate_inclusion(:status, ["active", "disabled", "archived"])
    |> validate_rule_entries()
  end

  def rule_entries(%__MODULE__{rules: %{"entries" => entries}}) when is_list(entries), do: entries
  def rule_entries(%__MODULE__{rules: _}), do: []

  defp normalize_rules(attrs) when is_map(attrs) do
    case Map.get(attrs, "rules") do
      nil ->
        attrs

      %{"entries" => _entries} = rules ->
        Map.put(attrs, "rules", rules)

      rules when is_list(rules) ->
        wrapped = %{"entries" => rules}
        Map.put(attrs, "rules", wrapped)

      _other ->
        attrs
    end
  end

  defp validate_rule_entries(changeset) do
    rules = get_field(changeset, :rules) || %{}
    entries = Map.get(rules, "entries", [])

    valid? =
      is_list(entries) and
        Enum.all?(entries, fn
          %{
            "id" => _id,
            "category" => _category,
            "severity" => _severity,
            "action" => action,
            "plain_message" => _message,
            "matcher" => matcher
          }
          when is_map(matcher) ->
            action in ["warn", "block", "escalate_to_human"]

          _other ->
            false
        end)

    if valid? do
      changeset
    else
      add_error(changeset, :rules, "must contain additive ControlKeel rule entries")
    end
  end
end
