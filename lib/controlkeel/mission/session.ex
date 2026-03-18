defmodule ControlKeel.Mission.Session do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Finding, Invocation, Task, Workspace}

  schema "sessions" do
    field :title, :string
    field :objective, :string
    field :risk_tier, :string
    field :status, :string, default: "planned"
    field :budget_cents, :integer, default: 0
    field :daily_budget_cents, :integer, default: 0
    field :spent_cents, :integer, default: 0
    field :proxy_token, :string
    field :execution_brief, :map, default: %{}

    belongs_to :workspace, Workspace
    has_many :tasks, Task
    has_many :findings, Finding
    has_many :invocations, Invocation

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :title,
      :objective,
      :risk_tier,
      :status,
      :budget_cents,
      :daily_budget_cents,
      :spent_cents,
      :proxy_token,
      :execution_brief,
      :workspace_id
    ])
    |> ensure_proxy_token()
    |> validate_required([
      :title,
      :objective,
      :risk_tier,
      :status,
      :budget_cents,
      :daily_budget_cents,
      :spent_cents,
      :proxy_token,
      :execution_brief,
      :workspace_id
    ])
    |> validate_number(:budget_cents, greater_than_or_equal_to: 0)
    |> validate_number(:daily_budget_cents, greater_than_or_equal_to: 0)
    |> validate_number(:spent_cents, greater_than_or_equal_to: 0)
    |> unique_constraint(:proxy_token)
    |> assoc_constraint(:workspace)
  end

  defp ensure_proxy_token(changeset) do
    case get_field(changeset, :proxy_token) do
      value when is_binary(value) and value != "" ->
        changeset

      _ ->
        put_change(changeset, :proxy_token, generate_proxy_token())
    end
  end

  defp generate_proxy_token do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
