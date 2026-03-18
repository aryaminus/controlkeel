import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/controlkeel start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :controlkeel, ControlKeelWeb.Endpoint, server: true
end

config :controlkeel, ControlKeelWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :controlkeel, ControlKeel.Proxy,
  openai_upstream:
    System.get_env("CONTROLKEEL_PROXY_OPENAI_UPSTREAM") || "https://api.openai.com",
  anthropic_upstream:
    System.get_env("CONTROLKEEL_PROXY_ANTHROPIC_UPSTREAM") || "https://api.anthropic.com",
  semgrep_bin: System.get_env("CONTROLKEEL_SEMGREP_BIN") || "semgrep",
  timeout_ms: String.to_integer(System.get_env("CONTROLKEEL_PROXY_TIMEOUT_MS", "15000"))

if token = System.get_env("CONTROLKEEL_API_TOKEN") do
  config :controlkeel, :api_token, token
end

if webhook = System.get_env("CONTROLKEEL_WEBHOOK_URL") do
  config :controlkeel, :webhook_url, webhook
end

config :controlkeel, ControlKeel.Intent,
  default_provider: System.get_env("CONTROLKEEL_INTENT_DEFAULT_PROVIDER"),
  dev_fallback: System.get_env("CONTROLKEEL_INTENT_DEV_FALLBACK", "false") == "true",
  providers: %{
    anthropic: %{
      api_key: System.get_env("ANTHROPIC_API_KEY"),
      base_url:
        System.get_env("CONTROLKEEL_INTENT_ANTHROPIC_BASE_URL") ||
          "https://api.anthropic.com",
      model: System.get_env("CONTROLKEEL_INTENT_ANTHROPIC_MODEL") || "claude-sonnet-4.6"
    },
    openai: %{
      api_key: System.get_env("OPENAI_API_KEY"),
      base_url: System.get_env("CONTROLKEEL_INTENT_OPENAI_BASE_URL") || "https://api.openai.com",
      model: System.get_env("CONTROLKEEL_INTENT_OPENAI_MODEL") || "gpt-5.4"
    },
    openrouter: %{
      api_key: System.get_env("OPENROUTER_API_KEY"),
      base_url:
        System.get_env("CONTROLKEEL_INTENT_OPENROUTER_BASE_URL") || "https://openrouter.ai",
      model: System.get_env("CONTROLKEEL_INTENT_OPENROUTER_MODEL") || "openai/gpt-5.4-mini"
    },
    ollama: %{
      api_key: nil,
      base_url:
        System.get_env("CONTROLKEEL_OLLAMA_BASE_URL") || System.get_env("OLLAMA_HOST") ||
          "http://localhost:11434",
      model: System.get_env("CONTROLKEEL_INTENT_OLLAMA_MODEL") || "qwen2.5:7b"
    }
  }

if config_env() == :prod do
  database_path = ControlKeel.RuntimeDefaults.database_path()

  config :controlkeel, ControlKeel.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base = ControlKeel.RuntimeDefaults.secret_key_base()

  host = System.get_env("PHX_HOST") || "example.com"

  config :controlkeel, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :controlkeel, ControlKeelWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :controlkeel, ControlKeelWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :controlkeel, ControlKeelWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :controlkeel, ControlKeel.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
