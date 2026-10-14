defmodule ControlKeelWeb.OAuthLoginController do
  @moduledoc """
  Browser OAuth sign-in for Google and GitHub.

  Two-phase flow:

    * `GET /auth/:provider/request` — redirects the user to the OAuth provider.
    * `GET /auth/:provider/callback` — the provider redirects back here; the
      authorization code is exchanged, userinfo is fetched, the user is found
      or created, and the session is established.

  On any failure, the user is flashed an error and sent back to `/auth/login`.
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.OAuthProviders
  alias ControlKeel.Accounts.OrgIdentityProvider
  alias ControlKeel.Accounts.OrgIdentityProviders
  alias ControlKeel.Accounts.OAuthProviders.DefaultAdapter

  @doc "Phase 1 — redirect the user to the OAuth provider's authorization page"
  def request(conn, %{"provider" => provider_name}) do
    with {:ok, provider} <- safe_to_atom(provider_name),
         {:ok, %{url: url, session_params: session_params}} <-
           OAuthProviders.authorize_url(provider) do
      conn
      |> put_session(:oauth_session_params, session_params)
      |> put_session(:oauth_provider, provider_name)
      |> redirect(external: url)
    else
      {:error, :not_configured} ->
        conn
        |> put_flash(:error, "Sign-in with #{provider_name} is not configured.")
        |> redirect(to: ~p"/auth/login")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to start sign-in. Please try again.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  def request(conn, _params), do: redirect(conn, to: ~p"/auth/login")

  @doc "Phase 2 — handle the OAuth provider callback"
  def callback(conn, params) do
    provider_name = get_session(conn, :oauth_provider)
    session_params = get_session(conn, :oauth_session_params) || %{}

    with {:ok, provider} <- safe_to_atom(provider_name),
         {:ok, %{email: email, name: name}} <-
           OAuthProviders.callback(provider, params, session_params),
         {:ok, user, _created} <- Accounts.find_or_create_user(email, name) do
      invitation_token = get_session(conn, :pending_invitation_token)

      conn
      |> delete_session(:oauth_session_params)
      |> delete_session(:oauth_provider)
      |> delete_session(:pending_invitation_token)
      |> put_session(:current_user_id, user.id)
      |> put_session(:session_last_active, DateTime.utc_now() |> DateTime.to_iso8601())
      |> put_flash(:info, "Signed in with #{provider_display_name(provider_name)}.")
      |> redirect(
        to:
          if invitation_token do
            ~p"/invitations/#{invitation_token}"
          else
            ~p"/"
          end
      )
    else
      {:error, :not_configured} ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, "Sign-in with #{provider_name} is not configured.")
        |> redirect(to: ~p"/auth/login")

      {:error, :missing_email} ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, "Provider did not return an email address.")
        |> redirect(to: ~p"/auth/login")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, "Could not create your account. Please try again.")
        |> redirect(to: ~p"/auth/login")

      {:error, _reason} ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  @doc "Phase 1 — redirect to a tenant's own OIDC provider"
  def oidc_request(conn, %{"slug" => slug}) do
    with {:ok, provider} <- OrgIdentityProviders.fetch_by_slug(slug),
         {:ok, cfg} <- OrgIdentityProviders.assent_config(provider) do
      session_params = %{}

      case DefaultAdapter.oidc_authorize_url(cfg, session_params) do
        {:ok, %{url: url, session_params: sp}} ->
          conn
          |> put_session(:oidc_session_params, sp)
          |> put_session(:oidc_slug, slug)
          |> redirect(external: url)

        {:error, _reason} ->
          conn
          |> clear_oauth_session()
          |> put_flash(:error, "Could not start sign-in with this provider.")
          |> redirect(to: ~p"/auth/login")
      end
    else
      {:error, :undecryptable_secret} ->
        conn
        |> clear_oauth_session()
        |> put_flash(
          :error,
          "This identity provider is misconfigured. Contact your administrator."
        )
        |> redirect(to: ~p"/auth/login")

      _ ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, "Unknown identity provider.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc "Phase 2 — handle a tenant OIDC provider callback"
  def oidc_callback(conn, %{"slug" => slug} = params) do
    session_params = get_session(conn, :oidc_session_params) || %{}

    with {:ok, provider} <- OrgIdentityProviders.fetch_by_slug(slug),
         {:ok, cfg} <- OrgIdentityProviders.assent_config(provider),
         {:ok, %{email: email, name: name}} <-
           DefaultAdapter.oidc_callback(cfg, params, session_params),
         :ok <- check_domain(provider, email),
         {:ok, user, _created} <- Accounts.find_or_create_user(email, name) do
      conn
      |> clear_oauth_session()
      |> put_session(:current_user_id, user.id)
      |> put_session(:session_last_active, DateTime.utc_now() |> DateTime.to_iso8601())
      |> put_flash(:info, "Signed in with #{provider.name}.")
      |> redirect(to: ~p"/")
    else
      {:error, :email_not_verified} ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, "Your #{provider_name(conn)} email is not verified.")
        |> redirect(to: ~p"/auth/login")

      {:error, :domain_not_allowed} ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, "That email domain is not allowed for this provider.")
        |> redirect(to: ~p"/auth/login")

      {:error, :undecryptable_secret} ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, "This identity provider is misconfigured.")
        |> redirect(to: ~p"/auth/login")

      {:error, :account_disabled} ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, "This account has been disabled. Contact your administrator.")
        |> redirect(to: ~p"/auth/login")

      _ ->
        conn
        |> clear_oauth_session()
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  defp check_domain(provider, email) do
    if OrgIdentityProvider.domain_allowed?(provider, email) do
      :ok
    else
      {:error, :domain_not_allowed}
    end
  end

  defp provider_name(conn) do
    case get_session(conn, :oidc_slug) do
      nil -> "your identity provider"
      slug -> slug
    end
  end

  defp safe_to_atom("google"), do: {:ok, :google}
  defp safe_to_atom("github"), do: {:ok, :github}
  defp safe_to_atom(_), do: {:error, :invalid_provider}

  defp clear_oauth_session(conn) do
    conn
    |> delete_session(:oauth_session_params)
    |> delete_session(:oauth_provider)
    |> delete_session(:oidc_session_params)
    |> delete_session(:oidc_slug)
  end

  defp provider_display_name(provider_name) when is_binary(provider_name) do
    case provider_name do
      "github" -> "GitHub"
      "google" -> "Google"
      _ -> String.capitalize(provider_name)
    end
  end
end
