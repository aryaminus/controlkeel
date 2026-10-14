defmodule ControlKeel.Accounts.Org do
  @moduledoc """
  Organization grouping users for team workspaces, org budgets, and
  cross-workspace policies.

  Slug is a URL-safe stable identifier used in cloud routes and external
  references. Name is the human-readable display form.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.Membership

  @primary_key {:id, :id, autogenerate: true}
  schema "orgs" do
    field :name, :string
    field :slug, :string
    field :status, :string, default: "active"
    field :settings, :map, default: %{}

    has_many :memberships, Membership
    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @valid_statuses ~w(active disabled)
  @slug_regex ~r/^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$/

  # Single-segment paths declared before the `/:org_slug` live route in
  # `ControlKeelWeb.Router`. Without this, an org named e.g. "docs" would be
  # shadowed by `get "/docs"` and become unreachable at its canonical URL.
  # Existing colliding rows (if any) are left untouched — this only blocks new
  # inserts/renames; they remain reachable via `/organizations/:slug` listing.
  @reserved_slugs ~w(
    docs getting-started about contact privacy developers
    auth dashboard sessions findings benchmarks proofs
    cloud organizations policies skills observability invitations
    workspaces api proxy mcp oauth dev assets
  )

  def changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :slug, :status, :settings])
    |> validate_required([:name, :slug])
    |> update_change(:slug, &normalize_slug/1)
    |> validate_format(:slug, @slug_regex)
    |> validate_exclusion(:slug, @reserved_slugs, message: "is reserved")
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:name, min: 1, max: 200)
    |> unique_constraint(:slug)
  end

  defp normalize_slug(nil), do: nil
  defp normalize_slug(slug) when is_binary(slug), do: slug |> String.downcase() |> String.trim()
end
