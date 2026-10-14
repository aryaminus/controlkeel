defmodule ControlKeel.Accounts.OrgIdentityProviders do
  @moduledoc """
  CRUD and lookup for tenant-owned OIDC identity providers (issue #267).

  ## Secret handling

  `client_secret` is encrypted with `Phoenix.Token` under a dedicated salt
  before it reaches the database. Each tenant holds their own IdP credential
  now, so a plaintext column would mean one read of `org_identity_providers`
  exfiltrates every tenant's IdP secret simultaneously. Decryption failures
  return `:error` rather than raising, so a rotated `SECRET_KEY_BASE` produces
  a clear sign-in failure instead of a 500.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Accounts.OrgIdentityProvider
  alias ControlKeel.Repo
  alias ControlKeelWeb.Endpoint

  @secret_salt "org_identity_provider_secret"

  @doc """
  Create (or update) a provider for an org. Takes a plaintext
  `:client_secret` and stores it encrypted.
  """
  @spec upsert(integer(), map()) :: {:ok, OrgIdentityProvider.t()} | {:error, term()}
  def upsert(org_id, attrs) when is_integer(org_id) do
    attrs = stringify(attrs)

    with {:ok, secret} <- encrypt_secret(Map.get(attrs, "client_secret")) do
      changeset_attrs =
        attrs
        |> Map.put("org_id", org_id)
        |> Map.put("client_secret_encrypted", secret)
        |> Map.delete("client_secret")

      case Repo.get_by(OrgIdentityProvider, org_id: org_id, slug: changeset_attrs["slug"]) do
        nil ->
          %OrgIdentityProvider{}
          |> OrgIdentityProvider.changeset(changeset_attrs)
          |> Repo.insert()

        existing ->
          existing
          |> OrgIdentityProvider.changeset(changeset_attrs)
          |> Repo.update()
      end
    end
  end

  @doc "List every provider for an org (newest first)."
  @spec list_for_org(integer()) :: [OrgIdentityProvider.t()]
  def list_for_org(org_id) when is_integer(org_id) do
    OrgIdentityProvider
    |> where([p], p.org_id == ^org_id)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> Repo.all()
  end

  @doc "All usable providers across all orgs, for the login screen."
  @spec list_active() :: [OrgIdentityProvider.t()]
  def list_active do
    OrgIdentityProvider
    |> where([p], p.status == "active")
    |> order_by([p], asc: p.name)
    |> preload(:org)
    |> Repo.all()
  end

  @doc "Find a usable provider by its login slug."
  @spec fetch_by_slug(String.t()) :: {:ok, OrgIdentityProvider.t()} | {:error, :not_found}
  def fetch_by_slug(slug) when is_binary(slug) do
    slug = slug |> String.downcase() |> String.trim()

    case Repo.get_by(OrgIdentityProvider, slug: slug, status: "active") do
      %OrgIdentityProvider{} = provider -> {:ok, Repo.preload(provider, :org)}
      _ -> {:error, :not_found}
    end
  end

  @doc "Soft-delete a provider so any issued sessions can be audited later."
  @spec delete(integer(), integer()) :: {:ok, OrgIdentityProvider.t()} | {:error, :not_found}
  def delete(org_id, id) when is_integer(org_id) and is_integer(id) do
    case Repo.get_by(OrgIdentityProvider, org_id: org_id, id: id) do
      nil ->
        {:error, :not_found}

      provider ->
        provider
        |> OrgIdentityProvider.changeset(%{status: "disabled"})
        |> Repo.update()
    end
  end

  @doc """
  Decrypt a provider's client secret.

  Returns `{:error, :undecryptable_secret}` when the token cannot be verified
  (e.g. `SECRET_KEY_BASE` rotated), so the caller can fail the sign-in cleanly.
  """
  @spec client_secret(OrgIdentityProvider.t()) ::
          {:ok, String.t()} | {:error, :undecryptable_secret}
  def client_secret(%OrgIdentityProvider{client_secret_encrypted: encrypted})
      when is_binary(encrypted) and encrypted != "" do
    case Plug.Crypto.decrypt(key_base(), @secret_salt, encrypted, max_age: :infinity) do
      {:ok, secret} when is_binary(secret) -> {:ok, secret}
      _ -> {:error, :undecryptable_secret}
    end
  end

  def client_secret(_provider), do: {:error, :undecryptable_secret}

  @doc "Build the Assent config map for this provider."
  @spec assent_config(OrgIdentityProvider.t()) ::
          {:ok, map()} | {:error, :undecryptable_secret}
  def assent_config(%OrgIdentityProvider{} = provider) do
    with {:ok, secret} <- client_secret(provider) do
      {:ok,
       %{
         client_id: provider.client_id,
         client_secret: secret,
         base_url: provider.issuer,
         # Generic OIDC always requests these; a provider that cannot supply
         # `email_verified` will fail closed in the caller.
         scope: provider.scopes
       }}
    end
  end

  defp encrypt_secret(nil), do: {:ok, nil}
  defp encrypt_secret(""), do: {:ok, nil}

  defp encrypt_secret(secret) when is_binary(secret) do
    {:ok, Plug.Crypto.encrypt(key_base(), @secret_salt, secret, max_age: :infinity)}
  end

  # Derived from the app secret so rotating SECRET_KEY_BASE invalidates stored
  # IdP secrets (they can be re-entered by the tenant admin) rather than leaving
  # them permanently undecryptable.
  defp key_base, do: Endpoint.config(:secret_key_base)

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
