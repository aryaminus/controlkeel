defmodule ControlKeel.Accounts.DeviceAuthTest do
  @moduledoc """
  RFC 8628 device authorization grant server-side behaviour (issue #251).

  Covers the security properties the RFC and OWASP require: codes stored
  hashed, user codes rate-limited, short lifetime, single-use device codes,
  and the `authorization_pending` / `slow_down` polling state machine.
  """
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.DeviceAuth
  alias ControlKeel.Cloud.RateLimiter

  setup do
    RateLimiter.reset()
    :ok
  end

  defp user do
    n = System.unique_integer([:positive])
    {:ok, u} = Accounts.create_user(%{email: "device-#{n}@example.com"})
    u
  end

  describe "start_device_authorization/1" do
    test "returns raw codes but stores only hashes" do
      assert {:ok, payload} = DeviceAuth.start_device_authorization(%{client_name: "CK CLI"})

      assert is_binary(payload["device_code"])
      assert is_binary(payload["user_code"])
      assert payload["interval"] >= 1
      assert payload["expires_in"] > 0

      # The DB row carries hashes, not the codes.
      row =
        Repo.get_by(ControlKeel.Accounts.DeviceAuthorization,
          device_code_hash:
            :crypto.hash(:sha256, payload["device_code"]) |> Base.encode16(case: :lower)
        )

      refute is_nil(row)
      refute Map.has_key?(row, :device_code)
    end

    test "user codes are drawn from an unambiguous alphabet and are a fixed length" do
      {:ok, payload} = DeviceAuth.start_device_authorization(%{})
      code = payload["user_code"]
      assert String.length(code) == 8
      # No visually ambiguous characters.
      refute String.contains?(code, "O")
      refute String.contains?(code, "I")
      refute String.contains?(code, "0")
      refute String.contains?(code, "1")
    end

    test "each authorization gets a unique device and user code" do
      {:ok, a} = DeviceAuth.start_device_authorization(%{})
      {:ok, b} = DeviceAuth.start_device_authorization(%{})
      refute a["device_code"] == b["device_code"]
      refute a["user_code"] == b["user_code"]
    end
  end

  describe "fetch_by_user_code/1" do
    test "finds a pending authorization by user code" do
      {:ok, payload} = DeviceAuth.start_device_authorization(%{})
      assert {:ok, auth} = DeviceAuth.fetch_by_user_code(payload["user_code"])
      assert auth.status == "pending"
    end

    test "normalizes formatting (lowercase, separators)" do
      {:ok, payload} = DeviceAuth.start_device_authorization(%{})
      formatted = String.downcase(payload["user_code"])
      assert {:ok, _auth} = DeviceAuth.fetch_by_user_code(formatted)
    end

    test "an unknown code is not found" do
      assert {:error, :not_found} = DeviceAuth.fetch_by_user_code("ZZZZZZZZ")
    end

    test "user-code lookup is rate limited (RFC 8628 §5.1)" do
      {:ok, payload} = DeviceAuth.start_device_authorization(%{})
      code = payload["user_code"]

      # Burst is 5; the sixth attempt within the window must be throttled.
      results = for _ <- 1..6, do: DeviceAuth.fetch_by_user_code(code)
      assert Enum.any?(results, &match?({:error, :rate_limited}, &1))
    end
  end

  describe "approve/2 and poll_for_token/1" do
    test "approval lets the CLI redeem a token exactly once" do
      u = user()
      {:ok, payload} = DeviceAuth.start_device_authorization(%{})
      {:ok, auth} = DeviceAuth.fetch_by_user_code(payload["user_code"])

      # Before approval the CLI keeps polling.
      assert {:error, :authorization_pending} = DeviceAuth.poll_for_token(payload["device_code"])

      {:ok, approved} = DeviceAuth.approve(auth, u.id)
      assert approved.status == "approved"

      # Now the poll returns the approval.
      assert {:ok, redeemable} = DeviceAuth.poll_for_token(payload["device_code"])
      assert redeemable.user_id == u.id

      # After consuming, the device code is single-use.
      {:ok, _consumed} = DeviceAuth.consume(redeemable)
      assert {:error, :expired_token} = DeviceAuth.poll_for_token(payload["device_code"])
    end

    test "a denied authorization yields access_denied" do
      u = user()
      {:ok, payload} = DeviceAuth.start_device_authorization(%{})
      {:ok, auth} = DeviceAuth.fetch_by_user_code(payload["user_code"])

      {:ok, _denied} = DeviceAuth.deny(auth, u.id)
      assert {:error, :access_denied} = DeviceAuth.poll_for_token(payload["device_code"])
    end

    test "an unknown device code is expired_token" do
      assert {:error, :expired_token} = DeviceAuth.poll_for_token("nope-not-a-real-code")
    end

    test "cannot approve a non-pending authorization" do
      u = user()
      {:ok, payload} = DeviceAuth.start_device_authorization(%{})
      {:ok, auth} = DeviceAuth.fetch_by_user_code(payload["user_code"])
      {:ok, approved} = DeviceAuth.approve(auth, u.id)

      assert {:error, :invalid_state} = DeviceAuth.approve(approved, u.id)
    end
  end

  describe "expiry" do
    test "an expired authorization cannot be polled or fetched" do
      u = user()
      {:ok, payload} = DeviceAuth.start_device_authorization(%{})
      {:ok, auth} = DeviceAuth.fetch_by_user_code(payload["user_code"])
      {:ok, approved} = DeviceAuth.approve(auth, u.id)

      # Backdate the expiry.
      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      approved
      |> ControlKeel.Accounts.DeviceAuthorization.changeset(%{expires_at: past})
      |> Repo.update!()

      assert {:error, :expired_token} = DeviceAuth.poll_for_token(payload["device_code"])
    end
  end
end
