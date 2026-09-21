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

  alias ControlKeel.Accounts

  def logout(conn, _params) do
    conn
    |> delete_session(:current_user_id)
    |> delete_session(:current_org_id)
    |> delete_session(:oauth_state)
    |> delete_session(:oauth_provider)
    |> delete_session(:oauth_session_params)
    |> delete_session(:session_last_active)
    |> delete_session(:pending_invitation_token)
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/auth/login")
  end

  @switch_token_max_age 300

  @doc """
  Switch the session's default organization (issue #141, R4).

  `current_org_id` is a default hint for unscoped landing pages only — never
  an access basis — so it is written exclusively here, after verifying an
  active membership. The switch arrives as a short-lived signed token minted
  by `OrganizationsLive` (LiveView events are CSRF-safe; a bare controller
  GET carrying a raw id would not be), bound to `(user_id, org_id)` and
  re-verified against the signed-in user and current memberships.

  Routes:
    GET /auth/org/:org_id?t=<token>&return_to=<path>
  """
  def switch_org(conn, %{"org_id" => org_id} = params) do
    user = conn.assigns[:current_user]
    return_to = safe_return_to(params["return_to"])

    with %{id: user_id} <- user,
         {:ok, %{user_id: ^user_id, org_id: token_org_id}} <- verify_switch_token(params["t"]),
         {^token_org_id, ""} <- Integer.parse(to_string(org_id)),
         %Accounts.Membership{} <- Accounts.get_active_membership(user_id, token_org_id) do
      conn
      |> put_session(:current_org_id, token_org_id)
      |> put_flash(:info, "Switched organization.")
      |> redirect(to: return_to)
    else
      _ ->
        conn =
          if user,
            do: put_flash(conn, :error, "Organization not found or unavailable."),
            else: put_flash(conn, :error, "Please sign in to switch organizations.")

        redirect(conn, to: if(user, do: "/organizations", else: "/auth/login"))
    end
  end

  defp verify_switch_token(token) when is_binary(token) do
    Phoenix.Token.verify(ControlKeelWeb.Endpoint, "org-switch", token,
      max_age: @switch_token_max_age
    )
  end

  defp verify_switch_token(_), do: {:error, :missing_token}

  # Same-origin redirect targets only: absolute paths without a host.
  defp safe_return_to(""), do: "/organizations"
  defp safe_return_to(nil), do: "/organizations"

  defp safe_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and
         not String.starts_with?(path, "//") and
         not String.contains?(path, "\\"),
       do: path,
       else: "/organizations"
  end

  defp safe_return_to(_), do: "/organizations"

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
