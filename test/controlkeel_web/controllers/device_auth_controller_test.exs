defmodule ControlKeelWeb.DeviceAuthControllerTest do
  @moduledoc """
  End-to-end RFC 8628 device flow over HTTP: request → browser approve → CLI
  polls → token issued (issue #251).
  """
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.DeviceAuth
  alias ControlKeel.Cloud.RateLimiter

  setup do
    RateLimiter.reset()
    n = System.unique_integer([:positive])
    {:ok, user} = Accounts.create_user(%{email: "device-e2e-#{n}@example.com"})
    %{user: user}
  end

  defp json_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, body)
  end

  test "full device flow: authorize → approve → token", %{conn: conn, user: user} do
    # 1. CLI requests a device authorization.
    conn = json_post(conn, "/device_authorization", %{client_id: "controlkeel-cli", scope: "cli"})
    payload = json_response(conn, 200)

    assert payload["device_code"]
    assert payload["user_code"]
    assert payload["interval"] >= 1

    # 2. Before approval, polling returns authorization_pending.
    pending =
      json_post(build_conn(), "/oauth/device_token", %{
        grant_type: "urn:ietf:params:oauth:grant-type:device_code",
        device_code: payload["device_code"]
      })

    assert json_response(pending, 400)["error"] == "authorization_pending"

    # 3. User approves in the browser.
    {:ok, auth} = DeviceAuth.fetch_by_user_code(payload["user_code"])
    {:ok, _approved} = DeviceAuth.approve(auth, user.id)

    # 4. CLI polls again and receives the token.
    issued =
      json_post(build_conn(), "/oauth/device_token", %{
        grant_type: "urn:ietf:params:oauth:grant-type:device_code",
        device_code: payload["device_code"]
      })

    token_body = json_response(issued, 200)
    assert token_body["access_token"]
    assert token_body["token_type"] == "Bearer"
    assert token_body["email"] == user.email

    # 5. The device code is single-use — replay is rejected.
    replay =
      json_post(build_conn(), "/oauth/device_token", %{
        grant_type: "urn:ietf:params:oauth:grant-type:device_code",
        device_code: payload["device_code"]
      })

    assert json_response(replay, 400)["error"] == "expired_token"
  end

  test "a denied flow returns access_denied", %{conn: conn, user: user} do
    conn = json_post(conn, "/device_authorization", %{client_id: "controlkeel-cli"})
    payload = json_response(conn, 200)

    {:ok, auth} = DeviceAuth.fetch_by_user_code(payload["user_code"])
    {:ok, _denied} = DeviceAuth.deny(auth, user.id)

    denied =
      json_post(build_conn(), "/oauth/device_token", %{
        grant_type: "urn:ietf:params:oauth:grant-type:device_code",
        device_code: payload["device_code"]
      })

    assert json_response(denied, 400)["error"] == "access_denied"
  end

  test "the token endpoint rejects an unsupported grant type" do
    bad = json_post(build_conn(), "/oauth/device_token", %{grant_type: "password"})
    assert json_response(bad, 400)["error"] == "unsupported_grant_type"
  end
end
