# BinWrapperTest isolates its System.cmd subprocess by copying the SQLite DB
# file — that approach doesn't apply to Postgres (server-based, not file-based).
# The wrapper itself is adapter-agnostic; the SQLite lane fully validates it.
excludes =
  [:performance] ++
    if System.get_env("CK_DB_ADAPTER") == "postgres", do: [:sqlite_only], else: []

ExUnit.start(max_cases: 1, exclude: excludes)
ControlKeel.Benchmark.list_suites()
Ecto.Adapters.SQL.Sandbox.mode(ControlKeel.Repo, :manual)
