defmodule ControlKeel.Accounts.WorkspaceToolPolicy do
  @moduledoc """
  Per-workspace tool catalog filter.

  Controls which hosted MCP tools a workspace is allowed to call. Three modes:

    - `"inherit"` (default) — workspace defers to the global `Policy` deny-list
      and rate-limit config. No additional restriction.
    - `"allowlist"` — only the tools listed in `tools` are permitted. All others
      are rejected with `{:error, {:policy, :tool_not_in_workspace_allowlist}}`.
    - `"denylist"` — the listed tools are additionally denied on top of the global
      policy. Tools not in the list follow normal global policy.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Workspace

  @modes ~w(inherit allowlist denylist)

  schema "workspace_tool_policies" do
    field :mode, :string, default: "inherit"
    field :tools, :string, default: "[]"

    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  def changeset(policy, attrs) do
    normalized = normalize_tools(attrs)

    policy
    |> cast(normalized, [:workspace_id, :mode, :tools])
    |> validate_required([:workspace_id, :mode, :tools])
    |> validate_inclusion(:mode, @modes)
    |> assoc_constraint(:workspace)
    |> unique_constraint(:workspace_id)
  end

  @doc "Returns the tools list decoded from the JSON text field."
  def decode_tools(%__MODULE__{tools: json}) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  def decode_tools(_), do: []

  defp normalize_tools(%{tools: tools} = attrs) when is_list(tools),
    do: %{attrs | tools: Jason.encode!(tools)}

  defp normalize_tools(attrs), do: attrs

  @doc "Valid mode identifiers."
  def modes, do: @modes
end
