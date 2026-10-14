defmodule ControlKeel.Accounts.UserOffboardingTest do
  @moduledoc """
  Offboarding has to actually revoke access.

  `disable_user/1` existed but had **no production call site**, and no
  authentication path read `user.status` — so disabling an account did nothing:
  the user kept signing in through OAuth and kept their live session. A SaaS
  that cannot offboard a single user cannot answer "who still has access?".

  These tests pin the three boundaries that must honor the flag.
  """
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts

  defp user_fixture do
    n = System.unique_integer([:positive])
    {:ok, user} = Accounts.create_user(%{email: "offboard-#{n}@example.com"})
    user
  end

  describe "user_active?/1" do
    test "an active user is active and a disabled user is not" do
      user = user_fixture()
      assert Accounts.user_active?(user)

      {:ok, disabled} = Accounts.disable_user(user.id)
      refute Accounts.user_active?(disabled)
    end

    test "a disabled user can be re-enabled" do
      user = user_fixture()
      {:ok, _} = Accounts.disable_user(user.id)

      {:ok, reenabled} = Accounts.enable_user(user.id)
      assert Accounts.user_active?(reenabled)
    end
  end

  describe "find_or_create_user/2 (the login boundary)" do
    test "a disabled account cannot sign in again" do
      user = user_fixture()
      {:ok, _} = Accounts.disable_user(user.id)

      assert {:error, :account_disabled} =
               Accounts.find_or_create_user(user.email, user.name)
    end

    test "an active account still signs in" do
      user = user_fixture()

      assert {:ok, found, false} = Accounts.find_or_create_user(user.email, user.name)
      assert found.id == user.id
    end

    test "an unknown email still creates a user" do
      n = System.unique_integer([:positive])

      assert {:ok, _user, true} =
               Accounts.find_or_create_user("brand-new-#{n}@example.com", "New")
    end
  end
end
