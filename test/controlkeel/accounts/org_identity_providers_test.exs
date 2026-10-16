defmodule ControlKeel.Accounts.OrgIdentityProvidersTest do
  @moduledoc """
  Tenant-owned OIDC identity providers (issue #267).

  The point of moving IdP config into the database is that each tenant controls
  their own credential — so the secret must be encrypted at rest, and the
  provider must not be usable as a generic open door into any tenant.
  """
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.OrgIdentityProvider
  alias ControlKeel.Accounts.OrgIdentityProviders

  setup do
    n = System.unique_integer([:positive])
    {:ok, owner} = Accounts.create_user(%{email: "idp-owner-#{n}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{name: "IdP Org #{n}", slug: "idp-org-#{n}"})

    %{org: org, owner: owner}
  end

  defp attrs(slug, overrides \\ %{}) do
    Map.merge(
      %{
        "slug" => slug,
        "name" => "Acme SSO",
        "issuer" => "https://idp.acme.example",
        "client_id" => "client-abc",
        "client_secret" => "super-secret-value",
        "scopes" => "openid email profile"
      },
      overrides
    )
  end

  describe "secret handling" do
    test "the client secret is encrypted at rest, not stored plaintext", %{org: org} do
      assert {:ok, provider} = OrgIdentityProviders.upsert(org.id, attrs("acme"))

      row = Repo.get_by(OrgIdentityProvider, id: provider.id)
      refute row.client_secret_encrypted == "super-secret-value"
      refute String.contains?(row.client_secret_encrypted, "super-secret-value")
    end

    test "the secret round-trips for use in the Assent config", %{org: org} do
      {:ok, _} = OrgIdentityProviders.upsert(org.id, attrs("acme"))
      {:ok, provider} = OrgIdentityProviders.fetch_by_slug("acme")

      assert {:ok, cfg} = OrgIdentityProviders.assent_config(provider)
      assert cfg.client_secret == "super-secret-value"
      assert cfg.client_id == "client-abc"
      assert cfg.base_url == "https://idp.acme.example"
    end

    test "a corrupt/rotated secret fails closed rather than raising", %{org: org} do
      {:ok, provider} = OrgIdentityProviders.upsert(org.id, attrs("acme"))

      provider
      |> Ecto.Changeset.change(client_secret_encrypted: "garbage")
      |> Repo.update!()

      # Re-read so we exercise the stored (corrupt) value, not the stale struct.
      corrupted = Repo.get_by(OrgIdentityProvider, id: provider.id)
      assert OrgIdentityProviders.client_secret(corrupted) == {:error, :undecryptable_secret}
    end
  end

  describe "isolation" do
    test "providers are scoped per org", %{org: org} do
      n = System.unique_integer([:positive])
      {:ok, other_owner} = Accounts.create_user(%{email: "other-#{n}@example.com"})

      {:ok, other_org} =
        Accounts.create_org_with_owner(other_owner.id, %{
          name: "Other #{n}",
          slug: "other-org-#{n}"
        })

      {:ok, _} = OrgIdentityProviders.upsert(org.id, attrs("mine"))

      assert [mine] = OrgIdentityProviders.list_for_org(org.id)
      assert mine.slug == "mine"
      assert OrgIdentityProviders.list_for_org(other_org.id) == []
    end

    test "the same slug can exist in two orgs", %{org: org} do
      n = System.unique_integer([:positive])
      {:ok, other_owner} = Accounts.create_user(%{email: "dup-#{n}@example.com"})

      {:ok, other_org} =
        Accounts.create_org_with_owner(other_owner.id, %{
          name: "Dup #{n}",
          slug: "dup-org-#{n}"
        })

      assert {:ok, _} = OrgIdentityProviders.upsert(org.id, attrs("shared"))
      assert {:ok, _} = OrgIdentityProviders.upsert(other_org.id, attrs("shared"))
    end

    test "deleting a provider disables it so it stops appearing", %{org: org} do
      {:ok, provider} = OrgIdentityProviders.upsert(org.id, attrs("gone"))
      assert {:ok, _} = OrgIdentityProviders.delete(org.id, provider.id)

      assert {:error, :not_found} = OrgIdentityProviders.fetch_by_slug("gone")
    end
  end

  describe "domain restriction" do
    test "an unrestricted provider allows any domain" do
      assert OrgIdentityProvider.domain_allowed?(
               %OrgIdentityProvider{allowed_domains: []},
               "a@b.com"
             )
    end

    test "a restricted provider rejects other domains" do
      provider = %OrgIdentityProvider{allowed_domains: ["acme.com"]}
      assert OrgIdentityProvider.domain_allowed?(provider, "user@acme.com")
      refute OrgIdentityProvider.domain_allowed?(provider, "user@evil.com")
    end

    test "domain matching is case-insensitive" do
      provider = %OrgIdentityProvider{allowed_domains: ["acme.com"]}
      assert OrgIdentityProvider.domain_allowed?(provider, "User@ACME.com")
    end
  end

  describe "validation" do
    test "rejects a non-https issuer", %{org: org} do
      assert {:error, changeset} =
               OrgIdentityProviders.upsert(
                 org.id,
                 attrs("bad", %{"issuer" => "http://idp.example"})
               )

      assert Enum.any?(changeset.errors, fn {f, {m, _}} -> f == :issuer and m =~ "https" end)
    end

    test "rejects an unsafe slug", %{org: org} do
      assert {:error, _} = OrgIdentityProviders.upsert(org.id, attrs("Bad Slug!"))
    end
  end
end
