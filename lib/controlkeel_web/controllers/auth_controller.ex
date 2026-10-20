defmodule ControlKeelWeb.AuthController do
  @moduledoc """
  Browser auth session helpers.

  ## Invitation flow

  `start_invitation/2` stores the invitation token in the session before
  redirecting to OAuth. After the OAuth callback establishes a session,
  `OAuthLoginController.callback/2` checks for a stored invitation token and
  redirects back to the invitation page so the now-authenticated user can
  accept.

  Browser OAuth sign-in (Google + GitHub) does NOT use this path — it
  sets session keys directly inside `OAuthLoginController`.
  """

  use ControlKeelWeb, :controller

  def logout(conn, _params) do
    conn
    |> delete_session(:current_user_id)
    |> delete_session(:oauth_state)
    |> delete_session(:oauth_provider)
    |> delete_session(:oauth_session_params)
    |> delete_session(:session_last_active)
    |> delete_session(:pending_invitation_token)
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/auth/login")
  end

  @doc """
  Store an invitation token in the session and redirect to OAuth.

  Called when an unauthenticated user clicks "Sign in to accept" on the
  invitation page. After OAuth callback, the token is read from the session
  to redirect the user back to the invitation page.

  Routes:
    GET /auth/invitation/:token?provider=google
  """
  def start_invitation(conn, %{"token" => token} = params) do
    provider = params["provider"] || "google"

    conn
    |> put_session(:pending_invitation_token, token)
    |> redirect(to: ~p"/auth/#{provider}/request")
  end
end
