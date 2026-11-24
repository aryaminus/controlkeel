defmodule ControlKeelWeb.LoadCurrentUserDisabledTest do
  @moduledoc """
  A disabled account must lose access immediately, including mid-session.

  `LoadCurrentUser` is the single point every authenticated surface flows
  through, so gating there means an existing cookie stops working the moment
  the account is disabled — rather than only blocking the *next* sign-in.
  """

  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeelWeb.Plugs.LoadCurrentUser

  # put_flash/3 requires the flash to have been fetched (the :browser
  # pipeline's fetch_live_flash runs before this plug in production).
  defp session_conn(session) do
    build_conn()
    |> Plug.Conn.assign(:flash, %{})
    |> Plug.Test.init_test_session(session)
    |> LoadCurrentUser.call([])
  end

  test "a disabled user's session resolves to no current_user" do
    n = System.unique_integer([:positive])
    {:ok, user} = Accounts.create_user(%{email: "session-offboard-#{n}@example.com"})
    {:ok, _} = Accounts.disable_user(user.id)

    conn =
      session_conn(%{"current_user_id" => user.id})

    assert conn.assigns[:current_user] == nil
  end

  test "an active user's session still resolves" do
    n = System.unique_integer([:positive])
    {:ok, user} = Accounts.create_user(%{email: "session-active-#{n}@example.com"})

    conn =
      session_conn(%{"current_user_id" => user.id})

    assert conn.assigns[:current_user].id == user.id
  end

  test "a disabled user's session keys are cleared and the logout is explained" do
    n = System.unique_integer([:positive])
    {:ok, user} = Accounts.create_user(%{email: "session-clear-#{n}@example.com"})
    {:ok, _} = Accounts.disable_user(user.id)

    conn =
      session_conn(%{
        "current_user_id" => user.id,
        "session_last_active" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    # Both session keys are gone, so re-enabling the account later cannot
    # silently restore this session.
    assert Plug.Conn.get_session(conn, :current_user_id) == nil
    assert Plug.Conn.get_session(conn, :session_last_active) == nil

    # The login path explains the logout instead of it reading as a random one.
    assert conn.assigns.flash["error"] ==
             "This account has been disabled. Contact your administrator."
  end

  test "an unknown (erased) user id clears the session without a disabled flash" do
    conn =
      session_conn(%{
        "current_user_id" => 987_654_321,
        "session_last_active" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    assert conn.assigns[:current_user] == nil
    assert Plug.Conn.get_session(conn, :current_user_id) == nil
    refute conn.assigns.flash["error"]
  end

  test "a mounted LiveView of the disabled user is evicted to the login screen with an explanation" do
    original = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original)
      end
    end)

    n = System.unique_integer([:positive])
    {:ok, user} = Accounts.create_user(%{email: "evict-#{n}@example.com"})

    {:ok, view, _html} = live(session_conn(%{"current_user_id" => user.id}), ~p"/new/org")

    # Offboarding mid-session: the disable broadcast (parity with delete_user's
    # post-commit eviction) must drop mounted pages immediately, explaining why.
    assert {:ok, _} = Accounts.disable_user(user.id)

    assert_redirect(view, "/auth/login")
  end
end
