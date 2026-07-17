defmodule ControlKeel.Cloud.Mcp.ToolCall do
  @moduledoc """
  Persisted record of one hosted MCP or A2A tool dispatch authorization decision.

  Captures who tried to call what, against which resource, with which scopes,
  and whether it was allowed or denied. Stored argument data is intentionally
  shallow — only the top-level argument keys, never values — so the audit log
  stays useful for forensics without becoming a secrets sink.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Platform.ServiceAccount

  @primary_key {:id, :id, autogenerate: true}
  schema "cloud_mcp_tool_calls" do
    field :resource, :string
    field :tool_name, :string
    field :outcome, :string
    field :denial_reason, :string
    field :scopes_granted, :string
    field :argument_keys, :string
    field :requested_at, :utc_datetime

    belongs_to :workspace, Workspace
    belongs_to :service_account, ServiceAccount
  end

  @required ~w(resource tool_name outcome requested_at)a
  @valid_outcomes ~w(allowed denied)

  def changeset(call, attrs) do
    call
    |> cast(
      attrs,
      @required ++ ~w(workspace_id service_account_id denial_reason scopes_granted argument_keys)a
    )
    |> validate_required(@required)
    |> validate_inclusion(:outcome, @valid_outcomes)
    |> assoc_constraint(:workspace)
    |> assoc_constraint(:service_account)
  end
end
