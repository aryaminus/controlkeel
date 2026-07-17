defmodule ControlKeel.AccountsFixtures do
  @moduledoc false

  alias ControlKeel.Accounts

  def org_fixture(attrs \\ %{}) do
    {:ok, org} =
      attrs
      |> Enum.into(%{
        name: "Test Org",
        slug: "test-org-#{:rand.uniform(1_000_000)}",
        status: "active"
      })
      |> Accounts.create_org()

    org
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "user-#{:rand.uniform(1_000_000)}@example.com",
        name: "Test User",
        status: "active"
      })
      |> Accounts.create_user()

    user
  end
end
