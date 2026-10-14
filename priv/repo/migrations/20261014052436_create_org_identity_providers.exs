defmodule ControlKeel.Repo.Migrations.CreateOrgIdentityProviders do
  use Ecto.Migration

  # Per-organization identity providers (issue #267).
  #
  # Previously every tenant authenticated through ONE global Google/GitHub
  # OAuth app configured from env vars. That is not enterprise SSO: a customer
  # cannot bring their own IdP (Okta, Entra ID, Google Workspace, Keycloak,
  # Auth0, ...), and a single shared credential is a single point of compromise
  # across all tenants.
  #
  # Generic OIDC covers those IdPs without a new dependency - Assent's
  # `Assent.Strategy.OIDC` is already vendored and performs discovery + JWKS +
  # id_token signature/issuer/audience validation. SAML is deliberately out of
  # scope for GA (new dependency, XML signature handling, IdP metadata
  # lifecycle) and is tracked as a follow-up if enterprise demand requires it.
  def change do
    create table(:org_identity_providers) do
      add :org_id, references(:orgs, on_delete: :delete_all), null: false
      # "oidc" is the only kind for now; the column exists so SAML or others can
      # be added without another migration.
      add :kind, :string, null: false, default: "oidc"
      # Short stable handle used in the login URL, e.g. /auth/oidc/<slug>/request
      add :slug, :string, null: false
      add :name, :string, null: false
      # OIDC issuer. Assent discovers /.well-known/openid-configuration from it.
      add :issuer, :string, null: false
      add :client_id, :string, null: false
      # Encrypted at rest via Phoenix.Token; never stored in plaintext.
      add :client_secret_encrypted, :string, null: false
      add :scopes, :string, default: "openid email profile"
      add :status, :string, null: false, default: "active"
      # Optional email-domain restriction, e.g. ["acme.com"] limits this IdP to
      # those domains so a tenant's IdP cannot be used to sign in with a
      # personal address.
      add :allowed_domains, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:org_identity_providers, [:org_id, :slug])
    create index(:org_identity_providers, [:slug])
  end
end
