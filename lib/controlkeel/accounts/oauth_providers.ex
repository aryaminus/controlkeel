defmodule ControlKeel.Accounts.OAuthProviders do
  @moduledoc """
  OAuth identity-provider boundary for the browser login flow.

  Two providers are supported:

    * **Google** — OIDC authorize + token + id_token claims (email + name).
      The id_token signature is verified against Google's JWKS via Assent.
    * **GitHub** — OAuth2 authorize + token + `/user` fetch (email + name).

  Client IDs, secrets, and redirect URIs are read from
  `config :controlkeel, :oauth_providers`. By default `config/runtime.exs`
  sources them from the `GOOGLE_OAUTH_CLIENT_ID`,
  `GOOGLE_OAUTH_CLIENT_SECRET`, `GITHUB_OAUTH_CLIENT_ID`,
  `GITHUB_OAUTH_CLIENT_SECRET`, and optional `*_REDIRECT_URI` env vars.

  ## API

    * `configured/0` — list of provider atoms (`:google`, `:github`) that have
      their client_id + client_secret set.
    * `config_for/1` — `%{client_id:, client_secret:, redirect_uri:}` for a
      provider atom.
    * `authorize_url/1` — provider-specific authorize URL via Assent.
      Returns `{:ok, %{url:, session_params:}}`. The caller MUST persist
      `session_params` and pass them to `callback/3`.
    * `callback/3` — exchanges the code for tokens and returns
      `%{email:, name:}`. Provider-aware.

  ## Adapter

  The default implementation uses `Assent` directly. Tests can inject a fake
  adapter via `Application.get_env(:controlkeel, :oauth_provider_adapter)`.
  The adapter must export `authorize_url/3` and `callback/4` with the same
  signatures as the default.
  """

  @type provider :: :google | :github
  @type claims :: %{
          email: String.t(),
          name: String.t() | nil,
          email_verified: boolean()
        }
  @type session_params :: map()

  @callback authorize_url(provider(), map(), keyword()) ::
              {:ok, %{url: String.t(), session_params: session_params()}}
              | {:error, term()}

  @callback callback(provider(), map(), map(), keyword()) ::
              {:ok, claims()} | {:error, atom() | term()}

  @spec configured() :: [provider()]
  def configured do
    Enum.filter([:google, :github], &configured?/1)
  end

  @spec config_for(provider()) ::
          %{client_id: String.t(), client_secret: String.t(), redirect_uri: String.t()} | nil
  def config_for(provider) when provider in [:google, :github] do
    providers_config = Application.get_env(:controlkeel, :oauth_providers, [])
    cfg = Keyword.get(providers_config, provider) || []

    client_id = Keyword.get(cfg, :client_id)
    client_secret = Keyword.get(cfg, :client_secret)

    cond do
      is_nil(client_id) or client_id == "" ->
        nil

      is_nil(client_secret) or client_secret == "" ->
        nil

      true ->
        redirect_uri =
          case Keyword.get(cfg, :redirect_uri) do
            uri when is_binary(uri) ->
              if String.trim(uri) != "", do: uri, else: default_redirect_uri(provider)

            _ ->
              default_redirect_uri(provider)
          end

        %{
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri
        }
    end
  end

  def config_for(_), do: nil

  @spec authorize_url(provider(), keyword()) ::
          {:ok, %{url: String.t(), session_params: session_params()}} | {:error, term()}
  def authorize_url(provider, opts \\ [])
      when provider in [:google, :github] do
    case config_for(provider) do
      nil ->
        {:error, :not_configured}

      cfg ->
        adapter = Keyword.get(opts, :adapter, adapter())
        adapter.authorize_url(provider, cfg, opts)
    end
  end

  @spec callback(provider(), map(), map(), keyword()) ::
          {:ok, claims()} | {:error, atom() | term()}
  def callback(provider, params, session_params, opts \\ [])
      when provider in [:google, :github] and is_map(params) do
    case config_for(provider) do
      nil ->
        {:error, :not_configured}

      cfg ->
        adapter = Keyword.get(opts, :adapter, adapter())
        adapter.callback(provider, cfg, params, put_in(opts, [:session_params], session_params))
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp configured?(provider) do
    case config_for(provider) do
      nil -> false
      %{} -> true
    end
  end

  defp default_redirect_uri(provider) do
    "#{ControlKeelWeb.Endpoint.url()}/auth/#{provider}/callback"
  end

  defp adapter do
    Application.get_env(
      :controlkeel,
      :oauth_provider_adapter,
      ControlKeel.Accounts.OAuthProviders.DefaultAdapter
    )
  end
end
