defmodule ControlKeelWeb.LoadCurrentUserDisabledTest do
  @moduledoc """
  A disabled account must lose access immediately, including mid-session.

  `LoadCurrentUser` is the single point every authenticated surface flows
  through, so gating there means an existing cookie stops working the moment
  the account is disabled — rather than only blocking the *next* sign-in.
  """
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeelWeb.Plugs.LoadCurrentUser

  test "a disabled user's session resolves to no current_user" do
    n = System.unique_integer([:positive])
    {:ok, user} = Accounts.create_user(%{email: "session-offboard-#{n}@example.com"})
    {:ok, _} = Accounts.disable_user(user.id)

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> LoadCurrentUser.call([])

    assert conn.assigns[:current_user] == nil
  end

  test "an active user's session still resolves" do
    n = System.unique_integer([:positive])
    {:ok, user} = Accounts.create_user(%{email: "session-active-#{n}@example.com"})

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> LoadCurrentUser.call([])

    assert conn.assigns[:current_user].id == user.id
  end
end
