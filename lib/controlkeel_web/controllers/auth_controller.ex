defmodule ControlKeelWeb.AuthController do
  @moduledoc """
  Browser auth session helpers.

  ## Signed completion tokens

  LiveViews cannot call `put_session/3` directly because the session lives
  on the parent HTTP conn, not the live socket. The invitation flow
  establishes a session after a LiveView completes:

    * **Invitation auto-login** — `InvitationLive` accepts the invite, then
      redirects to `/auth/complete/:token` with a signed Phoenix.Token
      carrying `%{user_id, org_id}`. This controller verifies the token
      and sets the session keys. The invite token itself is single-use and
      already consumed by accept; the completion token is a separate
      short-lived signed payload.

  OAuth sign-in (`OAuthLoginController`) sets the session directly via
  `put_session/3` on the controller conn and does not use this endpoint.

  The signed token has a 60-second max-age so a stale completion link
  cannot be replayed.
  """

  use ControlKeelWeb, :controller

  @completion_salt "auth-completion"
  @completion_max_age 60

  def logout(conn, _params) do
    conn
    |> delete_session(:current_user_id)
    |> delete_session(:current_org_id)
    |> delete_session(:oidc_state)
    |> delete_session(:oidc_org_id)
    |> delete_session(:session_last_active)
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/auth/login")
  end

  @doc """
  Mint a signed completion token. Called by LiveViews that need to hand off
  to a controller to put session keys.
  """
  @spec sign_completion_token(integer(), integer()) :: String.t()
  def sign_completion_token(user_id, org_id) when is_integer(user_id) and is_integer(org_id) do
    Phoenix.Token.sign(
      ControlKeelWeb.Endpoint,
      @completion_salt,
      %{user_id: user_id, org_id: org_id}
    )
  end

  @doc """
  Complete a signup or invitation by setting session keys from a signed token.

  Routes:
    GET /auth/complete/:token
  """
  def complete(conn, %{"token" => token}) do
    case Phoenix.Token.verify(
           ControlKeelWeb.Endpoint,
           @completion_salt,
           token,
           max_age: @completion_max_age
         ) do
      {:ok, %{user_id: user_id, org_id: org_id}}
      when is_integer(user_id) and is_integer(org_id) ->
        conn
        |> put_session(:current_user_id, user_id)
        |> put_session(:current_org_id, org_id)
        |> put_session(:session_last_active, DateTime.utc_now() |> DateTime.to_iso8601())
        |> put_flash(:info, "Welcome to ControlKeel.")
        |> redirect(to: ~p"/cloud/projects")

      _ ->
        conn
        |> put_flash(:error, "Sign-in link expired. Please try again.")
        |> redirect(to: ~p"/auth/login")
    end
  end
end
