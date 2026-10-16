defmodule ControlKeel.Platform.ServiceAccountExpiryTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Platform
  alias ControlKeel.Platform.ServiceAccount

  describe "create_service_account/2 expiry" do
    test "omitting an expiry never expires the credential" do
      workspace = workspace_fixture()

      assert {:ok, %{service_account: account, token: token}} =
               Platform.create_service_account(workspace.id, %{"name" => "forever"})

      assert account.expires_at == nil
      assert account.rotated_at == nil
      refute ServiceAccount.expired?(account)
      assert ServiceAccount.usable?(account)

      assert {:ok, authed} = Platform.authenticate_service_account(token)
      assert authed.expires_at == nil
      assert ServiceAccount.usable?(authed)
    end

    test "expires_in_days sets an expiry that many days out" do
      workspace = workspace_fixture()
      before = DateTime.utc_now()

      assert {:ok, %{service_account: account, token: token}} =
               Platform.create_service_account(workspace.id, %{
                 "name" => "bounded",
                 "expires_in_days" => 30
               })

      assert DateTime.compare(account.expires_at, DateTime.add(before, 30, :day)) in [:eq, :lt]
      assert DateTime.compare(account.expires_at, DateTime.add(before, 29, :day)) == :gt
      assert {:ok, _authed} = Platform.authenticate_service_account(token)
    end

    test "accepts a numeric string for expires_in_days" do
      workspace = workspace_fixture()
      before = DateTime.utc_now()

      assert {:ok, %{service_account: account}} =
               Platform.create_service_account(workspace.id, %{
                 "name" => "bounded",
                 "expires_in_days" => "7"
               })

      assert DateTime.compare(account.expires_at, DateTime.add(before, 7, :day)) in [:eq, :lt]
    end

    test "accepts an absolute expires_at in ISO8601" do
      workspace = workspace_fixture()
      expires_at = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

      assert {:ok, %{service_account: account}} =
               Platform.create_service_account(workspace.id, %{
                 "name" => "absolute",
                 "expires_at" => DateTime.to_iso8601(expires_at)
               })

      assert account.expires_at == expires_at
    end

    test "expires_in_days takes precedence over expires_at" do
      workspace = workspace_fixture()
      before = DateTime.utc_now()

      assert {:ok, %{service_account: account}} =
               Platform.create_service_account(workspace.id, %{
                 "name" => "both",
                 "expires_in_days" => 5,
                 "expires_at" => DateTime.to_iso8601(DateTime.add(before, 900, :day))
               })

      assert DateTime.compare(account.expires_at, DateTime.add(before, 5, :day)) in [:eq, :lt]
    end

    test "rejects a non-positive or malformed expires_in_days" do
      workspace = workspace_fixture()

      for value <- [0, -1, "0", "abc", "3.5", %{}] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Platform.create_service_account(workspace.id, %{
                   "name" => "bad",
                   "expires_in_days" => value
                 })

        assert_error_on(changeset, "expires_in_days")
      end

      assert Repo.aggregate(ServiceAccount, :count) == 0
    end

    test "rejects an explicit expires_at that is not in the future" do
      workspace = workspace_fixture()
      past = DateTime.utc_now() |> DateTime.add(-1, :minute)

      for value <- [past, DateTime.to_iso8601(past)] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Platform.create_service_account(workspace.id, %{
                   "name" => "stale",
                   "expires_at" => value
                 })

        assert_error_on(changeset, "expires_at")
      end

      assert Repo.aggregate(ServiceAccount, :count) == 0
    end

    test "rejects a malformed expires_at" do
      workspace = workspace_fixture()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Platform.create_service_account(workspace.id, %{
                 "name" => "bad",
                 "expires_at" => "not-a-timestamp"
               })

      assert_error_on(changeset, "expires_at")
    end
  end

  describe "expired?/1 boundary" do
    test "the expiry instant itself is already expired" do
      account = %ServiceAccount{expires_at: DateTime.utc_now() |> DateTime.truncate(:second)}

      assert ServiceAccount.expired?(account)
    end

    test "a future expiry is not expired" do
      account = %ServiceAccount{expires_at: DateTime.utc_now() |> DateTime.add(1, :second)}

      refute ServiceAccount.expired?(account)
      assert ServiceAccount.usable?(%{account | status: "active"})
    end

    test "a revoked account is unusable even with a live expiry" do
      revoked = %ServiceAccount{
        status: "revoked",
        expires_at: DateTime.utc_now() |> DateTime.add(1, :day)
      }

      refute ServiceAccount.expired?(revoked)
      refute ServiceAccount.usable?(revoked)
    end
  end

  describe "authenticate_service_account/1" do
    test "refuses an expired credential as unauthorized" do
      workspace = workspace_fixture()

      {:ok, %{service_account: account, token: token}} =
        Platform.create_service_account(workspace.id, %{"name" => "leaky"})

      assert {:ok, _authed} = Platform.authenticate_service_account(token)

      assert {:ok, _expired_account} = Platform.expire_service_account(account.id)

      assert {:error, :unauthorized} = Platform.authenticate_service_account(token)
    end

    test "refuses a credential that reaches its expiry" do
      workspace = workspace_fixture()

      {:ok, %{service_account: account, token: token}} =
        Platform.create_service_account(workspace.id, %{
          "name" => "short",
          "expires_in_days" => 1
        })

      account
      |> Ecto.Changeset.change(expires_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      assert {:error, :unauthorized} = Platform.authenticate_service_account(token)
      assert Repo.get(ServiceAccount, account.id).expires_at != nil
    end

    test "an expired credential is indistinguishable from an unknown token" do
      workspace = workspace_fixture()

      {:ok, %{service_account: account, token: token}} =
        Platform.create_service_account(workspace.id, %{"name" => "leaky"})

      {:ok, _} = Platform.expire_service_account(account.id)

      assert Platform.authenticate_service_account(token) ==
               Platform.authenticate_service_account("not-a-real-token")
    end

    test "a credential with a future expiry keeps authenticating" do
      workspace = workspace_fixture()

      {:ok, %{service_account: account, token: token}} =
        Platform.create_service_account(workspace.id, %{
          "name" => "bounded",
          "expires_in_days" => 30
        })

      assert {:ok, authed} = Platform.authenticate_service_account(token)
      assert authed.id == account.id
      assert authed.expires_at == account.expires_at
    end
  end

  describe "rotate_service_account/2" do
    test "preserves an existing expiry and stamps rotated_at" do
      workspace = workspace_fixture()
      before = DateTime.utc_now()

      {:ok, %{service_account: account, token: token}} =
        Platform.create_service_account(workspace.id, %{
          "name" => "bounded",
          "expires_in_days" => 30
        })

      assert {:ok, %{service_account: rotated, token: rotated_token}} =
               Platform.rotate_service_account(account.id)

      assert rotated.expires_at == account.expires_at
      assert DateTime.diff(rotated.rotated_at, before, :second) in -1..2
      assert rotated.last_used_at == nil

      assert {:error, :unauthorized} = Platform.authenticate_service_account(token)
      assert {:ok, _} = Platform.authenticate_service_account(rotated_token)
    end

    test "a non-expiring credential stays non-expiring" do
      workspace = workspace_fixture()

      {:ok, %{service_account: account}} =
        Platform.create_service_account(workspace.id, %{"name" => "forever"})

      assert {:ok, %{service_account: rotated}} = Platform.rotate_service_account(account.id)
      assert rotated.expires_at == nil
      assert rotated.rotated_at != nil
    end

    test "expires_in_days re-arms the lifetime from the rotation" do
      workspace = workspace_fixture()
      before = DateTime.utc_now()

      {:ok, %{service_account: account, token: token}} =
        Platform.create_service_account(workspace.id, %{
          "name" => "bounded",
          "expires_in_days" => 1
        })

      assert {:ok, %{service_account: rotated, token: rotated_token}} =
               Platform.rotate_service_account(account.id, expires_in_days: 30)

      assert DateTime.compare(rotated.expires_at, DateTime.add(before, 30, :day)) in [:eq, :lt]
      assert {:ok, _} = Platform.authenticate_service_account(rotated_token)
      assert {:error, :unauthorized} = Platform.authenticate_service_account(token)
    end

    test "expires_at: nil clears the expiry explicitly" do
      workspace = workspace_fixture()

      {:ok, %{service_account: account}} =
        Platform.create_service_account(workspace.id, %{
          "name" => "bounded",
          "expires_in_days" => 30
        })

      assert {:ok, %{service_account: rotated}} =
               Platform.rotate_service_account(account.id, expires_at: nil)

      assert rotated.expires_at == nil
    end

    test "refuses to rotate an expired account without a fresh expiry" do
      workspace = workspace_fixture()

      {:ok, %{service_account: account}} =
        Platform.create_service_account(workspace.id, %{"name" => "leaky"})

      {:ok, _} = Platform.expire_service_account(account.id)

      assert {:error, :expired} = Platform.rotate_service_account(account.id)
      assert {:error, :not_found} = Platform.rotate_service_account(-1)

      assert {:ok, %{service_account: revived, token: token}} =
               Platform.rotate_service_account(account.id, expires_in_days: 30)

      assert revived.expires_at != nil
      assert {:ok, _} = Platform.authenticate_service_account(token)
    end

    test "a rotation on a revoked account re-activates it" do
      workspace = workspace_fixture()

      {:ok, %{service_account: account}} =
        Platform.create_service_account(workspace.id, %{"name" => "revoked"})

      {:ok, _} = Platform.revoke_service_account(account.id)

      assert {:ok, %{service_account: rotated}} = Platform.rotate_service_account(account.id)
      assert rotated.status == "active"
      assert rotated.expires_at == nil
    end
  end

  describe "expiry administration" do
    test "expire_service_account/1 expires without changing status" do
      workspace = workspace_fixture()

      {:ok, %{service_account: account}} =
        Platform.create_service_account(workspace.id, %{"name" => "leaky"})

      assert {:ok, expired_account} = Platform.expire_service_account(account.id)
      assert expired_account.status == "active"
      assert ServiceAccount.expired?(expired_account)
      assert {:error, :not_found} = Platform.expire_service_account(-1)
    end

    test "update_service_account_expiry/2 extends an expired credential" do
      workspace = workspace_fixture()
      before = DateTime.utc_now()

      {:ok, %{service_account: account, token: token}} =
        Platform.create_service_account(workspace.id, %{"name" => "leaky"})

      {:ok, _} = Platform.expire_service_account(account.id)

      assert {:ok, updated} =
               Platform.update_service_account_expiry(account.id, expires_in_days: 10)

      assert DateTime.compare(updated.expires_at, DateTime.add(before, 10, :day)) in [:eq, :lt]
      assert {:ok, _} = Platform.authenticate_service_account(token)
    end

    test "update_service_account_expiry/2 accepts an absolute past expiry" do
      workspace = workspace_fixture()
      past = DateTime.utc_now() |> DateTime.add(-2, :hour) |> DateTime.truncate(:second)

      {:ok, %{service_account: account, token: token}} =
        Platform.create_service_account(workspace.id, %{"name" => "leaky"})

      assert {:ok, updated} = Platform.update_service_account_expiry(account.id, expires_at: past)
      assert updated.expires_at == past
      assert {:error, :unauthorized} = Platform.authenticate_service_account(token)
    end

    test "update_service_account_expiry/2 requires an explicit expiry" do
      workspace = workspace_fixture()

      {:ok, %{service_account: account}} =
        Platform.create_service_account(workspace.id, %{"name" => "bounded"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Platform.update_service_account_expiry(account.id)

      assert_error_on(changeset, "expires_at")
      assert {:error, :not_found} = Platform.update_service_account_expiry(-1, expires_in_days: 1)
    end

    test "the NHI lifecycle summary reports expiry state" do
      workspace = workspace_fixture()

      {:ok, %{service_account: expiring}} =
        Platform.create_service_account(workspace.id, %{
          "name" => "expiring",
          "expires_in_days" => 1
        })

      {:ok, %{service_account: _forever}} =
        Platform.create_service_account(workspace.id, %{"name" => "forever"})

      {:ok, _} = Platform.expire_service_account(expiring.id)

      summary = Platform.nhi_lifecycle_summary(workspace.id)

      assert summary.total == 2
      assert summary.active == 2
      assert summary.expired == 1

      by_name = Map.new(summary.identities, &{&1.name, &1})
      assert by_name["expiring"].expired
      assert by_name["expiring"].expires_at != nil
      refute by_name["forever"].expired
      assert by_name["forever"].expires_at == nil
    end
  end

  # Expiry keys are not schema fields, so Ecto keeps their changeset errors
  # keyed by the string the caller supplied.
  defp assert_error_on(changeset, field) do
    assert Enum.any?(changeset.errors, fn {key, {_message, _opts}} ->
             to_string(key) == field
           end)
  end
end
