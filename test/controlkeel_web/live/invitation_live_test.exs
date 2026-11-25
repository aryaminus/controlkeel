defmodule ControlKeelWeb.InvitationLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.RateLimiter

  setup do
    RateLimiter.reset()

    previous = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      RateLimiter.reset()

      if is_nil(previous) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, previous)
      end
    end)

    n = System.unique_integer([:positive])
    {:ok, owner} = Accounts.create_user(%{email: "owner-#{n}@example.com"})
    {:ok, invitee} = Accounts.create_user(%{email: "invitee-#{n}@example.com"})

    {:ok, org} =
      Accounts.create_org_with_owner(owner.id, %{name: "Org #{n}", slug: "org-#{n}"})

    {:ok, membership, token} =
      Accounts.invite_member(invitee.id, org.id, invited_by_user_id: owner.id)

    {:ok, org: org, membership: membership, token: token}
  end

  test "renders the invitation preview with its expiry", %{
    conn: conn,
    token: token,
    org: org,
    membership: membership
  } do
    {:ok, _view, html} = live(conn, "/invitations/#{token}")

    assert html =~ org.name
    assert html =~ "Expires"
    assert html =~ Calendar.strftime(membership.expires_at, "%Y-%m-%d")
  end

  test "renders the rate-limited state instead of crashing when the bucket is empty", %{
    conn: conn,
    token: token
  } do
    drain_invitation_bucket()

    {:ok, _view, html} = live(conn, "/invitations/#{token}")

    assert html =~ "Too many requests"
    assert html =~ "Try again"
    refute html =~ "Sign in to accept"
  end

  # Same budget the LiveView uses (burst 40 / refill 1.0), so the bucket is
  # empty for the two mount passes performed by `live/2`.
  defp drain_invitation_bucket do
    for _ <- 1..40 do
      RateLimiter.hit_key("ip:invitation:127.0.0.1", burst: 40, refill_per_sec: 1.0)
    end
  end
end
