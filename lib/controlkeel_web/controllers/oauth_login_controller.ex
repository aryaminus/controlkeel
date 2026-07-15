defmodule ControlKeelWeb.OAuthLoginController do
  @moduledoc """
  OAuth login flow using Assent strategies.

  Two-phase flow:
    1. `GET /auth/:provider/request`  — redirects the user to the OAuth provider
    2. `GET /auth/:provider/callback` — the provider redirects back here; the
       authorization code is exchanged, userinfo is fetched, the user is found
       or created, and the session is established.

  Rate-limiting of the request endpoint should be handled at the reverse-proxy
  layer (e.g. Cloudflare / nginx). No `current_org_id` is set during login —
  org selection happens post-login.
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Accounts

  @doc "Phase 1 — redirect the user to the OAuth provider's authorization page"
  def request(conn, %{"provider" => provider_name}) do
    with {:ok, provider} <- safe_to_atom(provider_name),
         {:ok, config} <- provider_config(provider),
         {:ok, %{url: url, session_params: session_params}} <-
           config[:strategy].authorize_url(config) do
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
    session_params = get_session(conn, :oauth_session_params)

    with {:ok, provider} <- safe_to_atom(provider_name),
         {:ok, config} <- provider_config(provider) do
      config = Keyword.put(config, :session_params, session_params)

      case config[:strategy].callback(config, params) do
        {:ok, %{user: user_info, token: _token}} ->
          handle_successful_auth(conn, provider_name, user_info)

        {:error, _reason} ->
          conn
          |> clear_oauth_session()
          |> put_flash(:error, "Authentication failed. Please try again.")
          |> redirect(to: ~p"/auth/login")
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid authentication request.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  defp handle_successful_auth(conn, provider_name, user_info) do
    provider_uid = extract_provider_uid(user_info)

    case Accounts.find_or_create_oauth_user(provider_name, provider_uid, user_info) do
      {:ok, user} ->
        conn
        |> clear_oauth_session()
        |> put_session(:current_user_id, user.id)
        |> put_session(:session_last_active, DateTime.utc_now() |> DateTime.to_iso8601())
        |> put_flash(:info, "Signed in with #{String.capitalize(provider_name)}")
        |> redirect(to: ~p"/cloud/projects")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not complete sign-in. Please contact support.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  defp extract_provider_uid(user_info) do
    to_string(user_info["sub"] || user_info["id"])
  end

  defp provider_config(provider) when is_atom(provider) do
    case Accounts.oauth_provider_config(provider) do
      nil -> {:error, :not_configured}
      config -> {:ok, config}
    end
  end

  defp safe_to_atom(nil), do: {:error, :invalid_provider}

  defp safe_to_atom(name) when is_binary(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> {:error, :invalid_provider}
  end

  defp clear_oauth_session(conn) do
    conn
    |> delete_session(:oauth_session_params)
    |> delete_session(:oauth_provider)
  end
end
