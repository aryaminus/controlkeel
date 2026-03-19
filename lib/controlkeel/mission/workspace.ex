defmodule ControlKeel.Mission.Workspace do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Memory.Record
  alias ControlKeel.Mission.Session

  schema "workspaces" do
    field :name, :string
    field :slug, :string
    field :industry, :string
    field :agent, :string
    field :budget_cents, :integer, default: 0
    field :compliance_profile, :string
    field :status, :string, default: "draft"

    has_many :sessions, Session
    has_many :memory_records, Record

    timestamps(type: :utc_datetime)
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :slug, :industry, :agent, :budget_cents, :compliance_profile, :status])
    |> validate_required([
      :name,
      :slug,
      :industry,
      :agent,
      :budget_cents,
      :compliance_profile,
      :status
    ])
    |> validate_number(:budget_cents, greater_than_or_equal_to: 0)
    |> update_change(:slug, &normalize_slug/1)
    |> unique_constraint(:slug)
  end

  defp normalize_slug(nil), do: nil

  defp normalize_slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
