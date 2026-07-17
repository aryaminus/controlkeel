defmodule ControlKeel.Mission.WorkspaceAgent do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.User
  alias ControlKeel.Mission.Workspace

  @valid_roles ~w(primary specialized ephemeral)
  @valid_statuses ~w(active paused retired)
  @valid_agent_types ~w(
    claude-code cursor windsurf kiro augment opencode codex-cli
    aider copilot gemini-cli vscode pi generic
  )

  schema "workspace_agents" do
    field :external_id, :string
    field :name, :string
    field :role, :string, default: "specialized"
    field :agent_type, :string
    field :status, :string, default: "active"
    field :scope, :map, default: %{}
    field :budget_cents, :integer, default: 0
    field :spent_cents, :integer, default: 0
    field :policy_overrides, :map, default: %{}
    field :sessions_count, :integer, default: 0
    field :last_active_at, :utc_datetime
    field :metadata, :map, default: %{}
    field :lock_version, :integer, default: 1

    belongs_to :workspace, Workspace
    belongs_to :maintainer, User, foreign_key: :maintainer_id

    timestamps(type: :utc_datetime)
  end

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :workspace_id,
      :external_id,
      :name,
      :role,
      :agent_type,
      :status,
      :scope,
      :budget_cents,
      :spent_cents,
      :policy_overrides,
      :maintainer_id,
      :sessions_count,
      :last_active_at,
      :metadata,
      :lock_version
    ])
    |> validate_required([:workspace_id, :name, :role, :agent_type])
    |> validate_inclusion(:role, @valid_roles)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:agent_type, @valid_agent_types)
    |> unique_constraint(:external_id)
    |> unique_constraint(:workspace_id, name: :workspace_agents_primary_unique)
    |> assoc_constraint(:workspace)
    |> assoc_constraint(:maintainer)
    |> maybe_generate_external_id()
  end

  @doc """
  Allowlist of fields safe to ship via cloud sync. `policy_overrides` and
  `scope` may contain workspace-scoped configuration including credentials —
  both pass through the redactor.
  """
  def sync_fields do
    {:include,
     [
       :id,
       :external_id,
       :workspace_id,
       :name,
       :role,
       :agent_type,
       :status,
       {:redact, :scope},
       :budget_cents,
       :spent_cents,
       {:redact, :policy_overrides},
       :maintainer_id,
       :sessions_count,
       :last_active_at,
       {:redact, :metadata},
       :lock_version,
       :inserted_at,
       :updated_at
     ]}
  end

  defp maybe_generate_external_id(changeset) do
    case get_field(changeset, :external_id) do
      nil ->
        ulid = generate_ulid()
        put_change(changeset, :external_id, "agent_#{ulid}")

      _ ->
        changeset
    end
  end

  defp generate_ulid do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :upper)
    |> String.slice(0, 26)
  end
end
