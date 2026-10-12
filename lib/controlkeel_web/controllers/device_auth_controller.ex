defmodule ControlKeelWeb.DeviceAuthController do
  @moduledoc """
  RFC 8628 OAuth 2.0 Device Authorization Grant endpoints (issue #251).

    * `POST /device_authorization` — the CLI requests a device authorization and
      receives `device_code`, `user_code`, `verification_uri`, `interval`, and
      `expires_in` (RFC 8628 §3.1/3.2).
    * `POST /oauth/device_token` — the CLI polls with
      `grant_type=urn:ietf:params:oauth:grant-type:device_code` and receives the
      token response or `authorization_pending` / `slow_down` / `access_denied` /
      `expired_token` (RFC 8628 §3.4/3.5).

  The browser approval page lives at `GET /device` (auth-gated separately).
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.DeviceAuth

  @device_grant_type "urn:ietf:params:oauth:grant-type:device_code"

  def authorize(conn, params) do
    case DeviceAuth.start_device_authorization(%{
           client_id: params["client_id"],
           scope: params["scope"] || ""
         }) do
      {:ok, payload} ->
        conn
        |> put_resp_content_type("application/json")
        # The device_code and user_code are secrets: never let a proxy cache them.
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("pragma", "no-cache")
        |> send_resp(200, Jason.encode!(payload))

      {:error, _changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_request"})
    end
  end

  def token(conn, params) do
    case grant_type(params) do
      @device_grant_type ->
        device_token(conn, params)

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "unsupported_grant_type"})
    end
  end

  defp device_token(conn, params) do
    device_code = params["device_code"] || ""

    case DeviceAuth.poll_for_token(device_code) do
      {:ok, authorization} ->
        issue_device_token(conn, authorization)

      {:error, :authorization_pending} ->
        oauth_error(conn, "authorization_pending")

      {:error, :slow_down} ->
        oauth_error(conn, "slow_down")

      {:error, :access_denied} ->
        oauth_error(conn, "access_denied")

      {:error, :expired_token} ->
        oauth_error(conn, "expired_token")
    end
  end

  # On approval we mint a user OAuth-style session token. The CLI stores it and
  # presents it as a bearer on subsequent API calls. Single use: the device code
  # is consumed so a replayed poll cannot re-issue a token.
  defp issue_device_token(conn, authorization) do
    user = Accounts.get_user(authorization.user_id)

    case user do
      nil ->
        oauth_error(conn, "invalid_request")

      user ->
        case DeviceAuth.consume(authorization) do
          {:ok, _} ->
            payload = %{
              "access_token" => issue_access_token(user),
              "token_type" => "Bearer",
              "email" => user.email
            }

            conn
            |> put_resp_header("cache-control", "no-store")
            |> json(payload)

          {:error, _} ->
            oauth_error(conn, "invalid_request")
        end
    end
  end

  # A signed, expiring bearer token scoped to the approving user. This is the
  # identity a logged-in CLI carries.
  defp issue_access_token(user) do
    Phoenix.Token.sign(
      ControlKeelWeb.Endpoint,
      "cli_access_token",
      %{
        "user_id" => user.id,
        "email" => user.email,
        "type" => "cli_user"
      }
    )
  end

  @doc false
  def verify_access_token(token) when is_binary(token) do
    case Phoenix.Token.verify(
           ControlKeelWeb.Endpoint,
           "cli_access_token",
           token,
           max_age: 60 * 60 * 24 * 30
         ) do
      {:ok, %{"user_id" => user_id} = claims} ->
        case Accounts.get_user(user_id) do
          nil -> :error
          _user -> {:ok, claims}
        end

      _ ->
        :error
    end
  end

  defp grant_type(%{"grant_type" => type}), do: type
  defp grant_type(_params), do: nil

  defp oauth_error(conn, code) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:bad_request)
    |> json(%{error: code})
  end
end
