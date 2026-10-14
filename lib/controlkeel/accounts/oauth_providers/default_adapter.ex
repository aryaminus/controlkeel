defmodule ControlKeel.Accounts.OAuthProviders.DefaultAdapter do
  @moduledoc """
  Assent-backed default adapter for `ControlKeel.Accounts.OAuthProviders`.

  Both providers go through Assent:

    * **Google** — `Assent.Strategy.Google` performs OIDC discovery, JWKS
      fetch, RS256 id_token signature verification, and issuer/audience
      claims validation.
    * **GitHub** — `Assent.Strategy.Github` performs plain OAuth2 token
      exchange plus `/user` (and `/user/emails` when needed) for claims.

  Tests inject a fake adapter via
  `Application.get_env(:controlkeel, :oauth_provider_adapter)`.
  """

  @behaviour ControlKeel.Accounts.OAuthProviders

  alias Assent.Strategy.{Github, Google}
  alias Assent.Strategy.OIDC

  @impl true
  def authorize_url(provider, cfg, opts) when provider in [:google, :github] do
    strategy(provider).authorize_url(assent_config(provider, cfg, opts))
  end

  @impl true
  def callback(provider, cfg, params, opts) when provider in [:google, :github] do
    session_params = Keyword.get(opts, :session_params, %{})

    config =
      assent_config(provider, cfg, opts)
      |> Keyword.put(:session_params, session_params)

    case strategy(provider).callback(config, params) do
      {:ok, %{user: user}} when is_map(user) ->
        email = user[:email] || user["email"]
        name = user[:name] || user["name"]

        if is_binary(email) and String.trim(email) != "" do
          {:ok, %{email: email, name: name}}
        else
          {:error, :missing_email}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Generic OIDC (tenant-owned IdP, issue #267) ─────────────────────────
  #
  # Separate from the google/github clauses above on purpose: those are global,
  # env-configured providers, while an org IdP is tenant data whose issuer and
  # secret come from the database (encrypted). Keeping them as distinct
  # functions means the tenant path never has to widen the `:google | :github`
  # enum that `OAuthProviders` guards on.

  @doc """
  Build the authorization URL for a tenant's generic OIDC provider.
  """
  def oidc_authorize_url(cfg, session_params) when is_map(cfg) do
    case OIDC.authorize_url(assent_oidc_config(cfg, session_params)) do
      {:ok, %{url: url}} -> {:ok, %{url: url, session_params: session_params}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Exchange the callback code for user claims using a tenant's OIDC provider.

  `Assent.Strategy.OIDC` validates the id_token signature against the issuer's
  JWKS and checks issuer and audience. We additionally require
  `email_verified`: a provider that omits it (or reports false) must not be
  able to establish an identity, which is the same fail-closed rule applied to
  Google/GitHub in #244.
  """
  def oidc_callback(cfg, params, session_params) when is_map(cfg) do
    config = assent_oidc_config(cfg, session_params)

    case OIDC.callback(config, params) do
      {:ok, %{user: user}} when is_map(user) ->
        email = user[:email] || user["email"]
        name = user[:name] || user["name"]
        verified? = truthy(user[:email_verified] || user["email_verified"])

        cond do
          not (is_binary(email) and String.trim(email) != "") ->
            {:error, :missing_email}

          not verified? ->
            {:error, :email_not_verified}

          true ->
            {:ok, %{email: email, name: name, email_verified: true}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp assent_oidc_config(cfg, session_params) do
    [
      client_id: cfg.client_id,
      client_secret: cfg.client_secret,
      base_url: cfg.issuer,
      scope: cfg.scopes,
      session_params: session_params
    ]
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp strategy(:google), do: Google
  defp strategy(:github), do: Github

  defp truthy(true), do: true
  defp truthy("true"), do: true
  defp truthy(_), do: false

  defp assent_config(_provider, cfg, _opts) do
    [
      client_id: cfg.client_id,
      client_secret: cfg.client_secret,
      redirect_uri: cfg.redirect_uri
    ]
  end
end
