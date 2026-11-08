import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
#
# Set CK_DB_ADAPTER=postgres to run the test suite against Postgres
# (used in the test-postgres CI lane).

if System.get_env("CK_DB_ADAPTER") == "postgres" do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL is required when CK_DB_ADAPTER=postgres"

  config :controlkeel, ControlKeel.Repo.Local,
    url: database_url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
else
  test_database =
    System.get_env("CK_TEST_DB") ||
      Path.expand("../priv/repo/controlkeel_test.db", __DIR__)

  pool_opts =
    if System.get_env("CK_TEST_SUBPROCESS") do
      [pool_size: 10]
    else
      [
        # SQLite-backed tests are more stable with a single pooled connection because
        # LiveView and benchmark flows can otherwise compete for overlapping write locks.
        pool_size: 1,
        pool: Ecto.Adapters.SQL.Sandbox
      ]
    end

  config :controlkeel, ControlKeel.Repo.Local,
    [
      database: test_database,
      busy_timeout: 15_000,
      journal_mode: :wal
    ] ++ pool_opts
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :controlkeel, ControlKeelWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  # Advertised URL — must match the test serving port so OAuth redirect URIs
  # and other external-facing links resolve correctly.
  url: [host: "localhost", scheme: "http", port: 4002],
  secret_key_base: "WKdOFVNJM1GGdfNm6wGhIiG+egBfTkfk/noG5Z1HAD1fsvZWVphETtOWJquCQdwZ",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :controlkeel, :analytics_telemetry_handler, false
config :controlkeel, :cloud_sender_periodic_enabled, false

# Mailer: capture deliveries in-memory so tests can assert on them.
config :controlkeel, :mailer_adapter, :test
