# BinWrapperTest isolates its System.cmd subprocess with a SQLite snapshot.
# That approach doesn't apply to Postgres (server-based, not file-based).
# The wrapper itself is adapter-agnostic; the SQLite lane fully validates it.
excludes =
  [:performance] ++
    if System.get_env("CK_DB_ADAPTER") == "postgres", do: [:sqlite_only], else: []

# Generated hook scripts keep state (last reported finding counts, one-time
# notices) under the user's state directory. Point every spawned hook at a
# throwaway directory so tests never read or write real home state.
hook_state_dir =
  Path.join(System.tmp_dir!(), "controlkeel-hook-state-#{System.unique_integer([:positive])}")

File.mkdir_p!(hook_state_dir)
System.put_env("CONTROLKEEL_HOOK_STATE_DIR", hook_state_dir)

ExUnit.start(max_cases: 1, exclude: excludes)
ControlKeel.Benchmark.list_suites()
Ecto.Adapters.SQL.Sandbox.mode(ControlKeel.Repo.Local, :manual)
