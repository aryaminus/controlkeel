defmodule ControlKeel.Accounts.OAuthTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts

  describe "find_or_create_oauth_user/3" do
    test "branch 1: returns the linked user when the identity already exists" do
      user_info = %{
        "sub" => "g-123",
        "email" => "alice@example.com",
        "email_verified" => true,
        "name" => "Alice",
        "picture" => "https://img.example.com/a.png"
      }

      assert {:ok, first_user} =
               Accounts.find_or_create_oauth_user("google", "g-123", user_info)

      assert {:ok, ^first_user} =
               Accounts.find_or_create_oauth_user(:google, "g-123", %{
                 user_info
                 | "name" => "Alice Updated"
               })

      identities = Accounts.list_oauth_identities(first_user)
      assert length(identities) == 1
      assert hd(identities).provider == "google"
      assert hd(identities).provider_uid == "g-123"
    end

    test "branch 2: links a new identity to an existing user when email is verified" do
      assert {:ok, invited} = Accounts.create_user(%{email: "bob@example.com", name: "Bob"})

      google_info = %{
        "sub" => "g-999",
        "email" => "BOB@example.com",
        "email_verified" => true,
        "name" => "Bob",
        "picture" => nil
      }

      assert {:ok, user} = Accounts.find_or_create_oauth_user("google", "g-999", google_info)
      assert user.id == invited.id

      identities = Accounts.list_oauth_identities(user)
      assert length(identities) == 1
      assert hd(identities).provider_email == "bob@example.com"
    end

    test "branch 3: creates a new user and identity when nothing matches" do
      github_info = %{
        "sub" => "gh-1",
        "email" => "carol@example.com",
        "email_verified" => true,
        "name" => "Carol",
        "picture" => "https://img.example.com/c.png"
      }

      assert {:ok, user} = Accounts.find_or_create_oauth_user("github", "gh-1", github_info)
      assert user.email == "carol@example.com"

      identities = Accounts.list_oauth_identities(user)
      assert length(identities) == 1
      assert hd(identities).provider == "github"
      assert hd(identities).provider_uid == "gh-1"
    end

    test "Gap 2.2: does not link by email when the provider email is unverified" do
      assert {:ok, victim} = Accounts.create_user(%{email: "eve@example.com"})

      unverified_info = %{
        "sub" => "gh-evil",
        "email" => "eve@example.com",
        "email_verified" => false,
        "name" => "Attacker"
      }

      assert {:error, _} =
               Accounts.find_or_create_oauth_user("github", "gh-evil", unverified_info)

      assert Accounts.list_oauth_identities(victim) == []
    end

    test "returns {:error, :missing_email} when the provider gives no email" do
      assert {:error, :missing_email} =
               Accounts.find_or_create_oauth_user("google", "x", %{"sub" => "x"})
    end
  end

  describe "unlink_oauth_identity/2" do
    test "removes a linked identity by provider name" do
      assert {:ok, user} =
               Accounts.find_or_create_oauth_user("google", "g-5", %{
                 "email" => "dan@example.com",
                 "email_verified" => true
               })

      assert {:ok, _identity} = Accounts.unlink_oauth_identity(user, "google")
      assert Accounts.list_oauth_identities(user) == []
    end

    test "returns {:error, :not_found} when no identity exists for the provider" do
      {:ok, user} = Accounts.create_user(%{email: "fran@example.com"})
      assert {:error, :not_found} = Accounts.unlink_oauth_identity(user, "google")
    end
  end

  describe "create_org_with_owner/2" do
    test "creates an org with an active owner membership for the user" do
      {:ok, user} = Accounts.create_user(%{email: "owner@example.com"})

      assert {:ok, {org, membership}} =
               Accounts.create_org_with_owner(user, %{name: "Acme", slug: "acme"})

      assert org.name == "Acme"
      assert org.slug == "acme"
      assert membership.user_id == user.id
      assert membership.org_id == org.id
      assert membership.role == "owner"
      assert membership.status == "active"
      assert membership.accepted_at
    end

    test "rolls back when the org attrs are invalid" do
      {:ok, user} = Accounts.create_user(%{email: "owner2@example.com"})

      assert {:error, %Ecto.Changeset{}} =
               Accounts.create_org_with_owner(user, %{name: "No Slug"})

      assert Accounts.list_memberships_for_user(user.id) == []
    end
  end
end
