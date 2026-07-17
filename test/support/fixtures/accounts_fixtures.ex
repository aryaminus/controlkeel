defmodule ControlKeel.AccountsFixtures do
  @moduledoc false

  alias ControlKeel.Accounts

  def org_fixture(attrs \\ %{}) do
    {:ok, org} =
      attrs
      |> Enum.into(%{
        name: "Test Org",
        slug: "test-org-#{System.unique_integer([:positive])}",
        status: "active"
      })
      |> Accounts.create_org()

    org
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "user-#{System.unique_integer([:positive])}@example.com",
        name: "Test User",
        status: "active"
      })
      |> Accounts.create_user()

    user
  end
end
