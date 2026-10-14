defmodule ControlKeel.Accounts.OrgIdentityProvider do
  @moduledoc """
  A tenant's own OpenID Connect identity provider (issue #267).

  Generic OIDC deliberately covers Okta, Microsoft Entra ID, Google Workspace,
  Keycloak, Auth0, Zitadel, GitLab and others through one integration, because
  `Assent.Strategy.OIDC` performs discovery, JWKS retrieval, and id_token
  signature/issuer/audience validation for any compliant issuer.

  `client_secret` is **encrypted at rest**. The whole point of moving IdP
  config into the database is that each tenant controls their own credential —
  storing that credential in plaintext would just relocate the shared-secret
  problem into a multi-tenant table where one SQL read exfiltrates every
  tenant's IdP secret at once.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.Org

  @kinds ~w(oidc)
  @statuses ~w(active disabled)

  schema "org_identity_providers" do
    field :kind, :string, default: "oidc"
    field :slug, :string
    field :name, :string
    field :issuer, :string
    field :client_id, :string
    field :client_secret_encrypted, :string
    field :scopes, :string, default: "openid email profile"
    field :status, :string, default: "active"
    field :allowed_domains, {:array, :string}, default: []

    belongs_to :org, Org

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :org_id,
      :kind,
      :slug,
      :name,
      :issuer,
      :client_id,
      :client_secret_encrypted,
      :scopes,
      :status,
      :allowed_domains
    ])
    |> validate_required([
      :org_id,
      :kind,
      :slug,
      :name,
      :issuer,
      :client_id,
      :client_secret_encrypted
    ])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:issuer, ~r{^https://}, message: "must be an https:// issuer")
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9_-]*$/,
      message: "must be lowercase alphanumeric with dashes or underscores"
    )
    |> update_change(:slug, &String.downcase/1)
    |> update_change(:allowed_domains, &normalize_domains/1)
    |> foreign_key_constraint(:org_id)
    |> unique_constraint([:org_id, :slug])
  end

  defp normalize_domains(nil), do: []

  defp normalize_domains(list) when is_list(list),
    do: Enum.map(list, &(&1 |> to_string() |> String.downcase() |> String.trim()))

  @doc "Whether the provider may be used for sign-in right now."
  def usable?(%__MODULE__{status: "active"}), do: true
  def usable?(%__MODULE__{}), do: false

  @doc """
  Whether this provider's IdP may authenticate the given email domain.

  An empty `allowed_domains` means unrestricted; a configured list restricts
  the provider to those domains so a tenant cannot use their corporate IdP to
  sign in with an arbitrary personal address.
  """
  def domain_allowed?(%__MODULE__{allowed_domains: []}, _email), do: true

  def domain_allowed?(%__MODULE__{allowed_domains: domains}, email) when is_binary(email) do
    domain = email |> String.split("@") |> List.last() |> String.downcase()
    String.trim(domain) in domains
  end

  def domain_allowed?(_provider, _email), do: true
end
