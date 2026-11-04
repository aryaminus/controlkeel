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

if level = System.get_env("LOGGER_LEVEL") do
  config :logger, level: String.to_existing_atom(level)
end

# Stdio MCP must own stdout exclusively. Dev normally starts esbuild/tailwind watchers
# that print build output to stdout and break JSON-RPC framing for Cursor and other hosts.
# CLI commands also need quiet mode to avoid debug SQL and build friction.
if System.get_env("CK_MCP_MODE") in ~w(1 true TRUE yes YES) or
     System.get_env("CK_CLI_MODE") in ~w(1 true TRUE yes YES) do
  config :controlkeel, ControlKeelWeb.Endpoint,
    watchers: [],
    server: false,
    code_reloader: false,
    # Avoid Phoenix dev loggers that attach to :logger and write free-form lines to stdout;
    # MCP stdio requires stdout to be JSON-RPC only (newline-delimited).
    # CLI commands should avoid unnecessary noise and build friction.
    live_reload: [
      web_console_logger: false,
      patterns: []
    ]

  # Anything on stdout after Content-Length framing corrupts the stream; clients then
  # hang and abort (~10s). Repo SQL logs default to :debug in dev and were observed on stdout.
  # CLI commands should avoid debug SQL noise for cleaner output.
  config :controlkeel, ControlKeel.Repo.Local, log: false
  config :controlkeel, ControlKeel.CloudRepo, log: false

  # OTP :logger default handler uses type :standard_io (stdout). Cursor parses stdout as
  # JSON-RPC only — log lines must go to stderr (logger_std_h type :standard_error).
  # CLI commands benefit from stderr logging to avoid corrupting structured output.
  config :logger, :default_handler, config: [type: :standard_error]

  # If the host did not set LOGGER_LEVEL (e.g. older .cursor/mcp.json), avoid :debug noise.
  if System.get_env("LOGGER_LEVEL") in [nil, ""] do
    config :logger, level: :warning
  end
end

config :controlkeel, ControlKeelWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :controlkeel, ControlKeel.Proxy,
  openai_upstream:
    System.get_env("CONTROLKEEL_PROXY_OPENAI_UPSTREAM") || "https://api.openai.com",
  anthropic_upstream:
    System.get_env("CONTROLKEEL_PROXY_ANTHROPIC_UPSTREAM") || "https://api.anthropic.com",
  gemini_upstream:
    System.get_env("CONTROLKEEL_PROXY_GEMINI_UPSTREAM") ||
      "https://generativelanguage.googleapis.com",
  semgrep_bin: System.get_env("CONTROLKEEL_SEMGREP_BIN") || "semgrep",
  timeout_ms: String.to_integer(System.get_env("CONTROLKEEL_PROXY_TIMEOUT_MS", "15000"))

# Parse the runtime mode through ControlKeel.Runtime.Mode.parse/1 so this stays
# in sync with Mode.current/0. A previous inline `case` only mapped "cloud" and
# sent "self_hosted" to :local, which made a self_hosted + DATABASE_URL release
# enter the SQLite branch and silently use SQLite instead of Postgres.
runtime_mode =
  System.get_env("CONTROLKEEL_RUNTIME_MODE", "local")
  |> ControlKeel.Runtime.Mode.parse()

config :controlkeel,
  runtime_mode: runtime_mode

# Identity providers for browser sign-in (`/auth/login`).
# Set *_CLIENT_ID and *_CLIENT_SECRET env vars to enable each button.
# Optional *_REDIRECT_URI overrides the derived /auth/<provider>/callback URL.
config :controlkeel, :oauth_providers,
  google: [
    client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_OAUTH_CLIENT_SECRET"),
    redirect_uri: System.get_env("GOOGLE_OAUTH_REDIRECT_URI")
  ],
  github: [
    client_id: System.get_env("GITHUB_OAUTH_CLIENT_ID"),
    client_secret: System.get_env("GITHUB_OAUTH_CLIENT_SECRET"),
    redirect_uri: System.get_env("GITHUB_OAUTH_REDIRECT_URI")
  ]

# Configure MCP tool groups for token optimization
# Adaptive mode is now enabled by default and will automatically select tool groups
# based on project type and usage patterns. This static config is only used as a fallback
# when adaptive mode is disabled or project_root is not available.
# Can be overridden via CK_TOOL_GROUPS environment variable
tool_groups =
  case System.get_env("CK_TOOL_GROUPS") do
    # Let adaptive mode handle it by default
    nil -> nil
    groups when is_binary(groups) -> String.split(groups, ",") |> Enum.map(&String.trim/1)
    _ -> nil
  end

if tool_groups do
  config :controlkeel, :mcp, tool_groups: tool_groups
end

retrieval_strategy =
  case System.get_env("CONTROLKEEL_MEMORY_RETRIEVAL_STRATEGY", "single_vector") do
    "late_interaction" -> :late_interaction
    "bm25" -> :bm25
    "hybrid_bm25_vector" -> :hybrid_bm25_vector
    "late_interaction_rerank" -> :late_interaction_rerank
    _ -> :single_vector
  end

config :controlkeel, :memory_retrieval_strategy, retrieval_strategy

if pdf_renderer = System.get_env("CONTROLKEEL_PDF_RENDERER") do
  renderer =
    case pdf_renderer do
      "chromic" -> :chromic
      _ -> :chromic
    end

  config :controlkeel, :pdf_renderer, renderer
end

if token = System.get_env("CONTROLKEEL_API_TOKEN") do
  config :controlkeel, :api_token, token
end

# Break-glass access for the /api/v1 bootstrap token.
#
# The bootstrap token is an emergency credential, not a platform superuser. In
# cloud/self_hosted mode it authorizes NOTHING unless it is explicitly enabled
# here AND scoped to a single workspace. Both values are required: an enabled
# but unscoped credential would still be a cross-tenant superuser, which is the
# failure mode this replaces.
#
# Deliberately opt-in per environment so a leaked CONTROLKEEL_API_TOKEN is not,
# by itself, a full compromise of every tenant.
if System.get_env("CONTROLKEEL_BREAK_GLASS_ENABLED") in ["true", "1"] do
  config :controlkeel, :break_glass_enabled, true

  config :controlkeel,
         :break_glass_workspace_id,
         System.get_env("CONTROLKEEL_BREAK_GLASS_WORKSPACE_ID")
end

if webhook = System.get_env("CONTROLKEEL_WEBHOOK_URL") do
  config :controlkeel, :webhook_url, webhook
end

config :controlkeel, ControlKeel.Intent,
  default_provider: System.get_env("CONTROLKEEL_INTENT_DEFAULT_PROVIDER"),
  dev_fallback: System.get_env("CONTROLKEEL_INTENT_DEV_FALLBACK", "true") == "true",
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
  database_path = ControlKeel.Runtime.Defaults.database_path()

  # One-time global -> project-local migration: if we resolved to a project DB
  # that doesn't exist yet, seed it from the legacy global DB before the Repo
  # opens. No-op for already-migrated projects or explicit DATABASE_PATH.
  ControlKeel.Runtime.Defaults.maybe_seed_project_database()

  # Postgres is configured whenever a remote mode (`:cloud` or `:self_hosted`)
  # is paired with a `DATABASE_URL`. In that case the local SQLite repo is
  # intentionally NOT configured — the dispatcher (lib/controlkeel/repo.ex)
  # must not be able to silently fall back to a laptop-local file when the
  # Postgres connection is misconfigured. If anything tries to use the local
  # repo directly it will fail loudly instead of writing to the wrong database.
  #
  # `:cloud` mode requires `DATABASE_URL` outright (raises). `:self_hosted`
  # may run without it during the self-host smoke test and laptop dev-runner
  # scenarios, in which case it falls through to the SQLite branch below.
  database_url = System.get_env("DATABASE_URL")

  if runtime_mode in [:cloud, :self_hosted] and database_url != nil do
    config :controlkeel, ControlKeel.CloudRepo,
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      ssl: System.get_env("ECTO_USE_SSL", "false") == "true"
  else
    if runtime_mode == :cloud do
      raise "DATABASE_URL is required when CONTROLKEEL_RUNTIME_MODE=cloud"
    end

    # Local mode, or :self_hosted dev-runner without DATABASE_URL. SQLite is
    # the source of truth; laptops sync to the hosted plane via
    # `controlkeel cloud push/pull`.
    config :controlkeel, ControlKeel.Repo.Local,
      database: database_path,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      journal_mode: :wal,
      synchronous: :normal,
      # Wait for a held SQLite lock instead of failing immediately. Multiple
      # controlkeel processes (CLI exports, the MCP server, hooks) share one
      # WAL database; without this, brief startup overlap surfaces as transient
      # "database is locked" errors. Dev/test already set this; prod did not.
      busy_timeout: String.to_integer(System.get_env("CONTROLKEEL_BUSY_TIMEOUT") || "15000"),
      queue_target: 50,
      queue_interval: 1_000
  end

  if endpoint = System.get_env("CONTROLKEEL_CLOUD_TELEMETRY_ENDPOINT") do
    config :controlkeel, cloud_telemetry_endpoint: endpoint
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base = ControlKeel.Runtime.Defaults.secret_key_base()
  url = ControlKeel.Runtime.Defaults.endpoint_url_config()

  config :controlkeel, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :controlkeel, ControlKeelWeb.Endpoint,
    url: url,
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
end
