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
        # Assent surfaces the provider's verification state for both providers:
        # Google from the OIDC `email_verified` claim, GitHub from the
        # primary entry's `verified` flag on /user/emails. Callers must not
        # trust an unverified email (see OAuthLoginController).
        email_verified = truthy(user[:email_verified] || user["email_verified"])

        if is_binary(email) and String.trim(email) != "" do
          {:ok, %{email: email, name: name, email_verified: email_verified}}
        else
          {:error, :missing_email}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Providers are inconsistent about the type of this flag; treat only a
  # literal true (or a truthy string) as verified. Absent ⇒ false (fail closed).
  defp truthy(true), do: true
  defp truthy("true"), do: true
  defp truthy(_), do: false

  # ── Private ─────────────────────────────────────────────────────────

  defp strategy(:google), do: Google
  defp strategy(:github), do: Github

  defp assent_config(_provider, cfg, _opts) do
    [
      client_id: cfg.client_id,
      client_secret: cfg.client_secret,
      redirect_uri: cfg.redirect_uri
    ]
  end
end
