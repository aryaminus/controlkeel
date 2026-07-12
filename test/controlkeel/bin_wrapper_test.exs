defmodule ControlKeel.BinWrapperTest do
  use ExUnit.Case, async: false

  # The wrapper subprocess is isolated by copying the SQLite DB file, which is
  # inherently SQLite-only. The shell script itself is adapter-agnostic.
  @moduletag :sqlite_only

  alias ControlKeel.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @wrapper Path.expand("../../bin/controlkeel", __DIR__)

  # The wrapper runs as a *subprocess* (System.cmd), so its DB writes are
  # outside the Ecto sandbox and would leak into the shared test DB.
  # Copy the already-migrated test DB to a throwaway path and point the
  # subprocess at it via CK_TEST_DB so any auto-bootstrap it triggers stays
  # fully isolated. Copying the migrated DB (rather than relying on the
  # subprocess to auto-migrate) avoids a migration-timing race on CI.
  setup do
    source_db = Repo.config() |> Keyword.fetch!(:database)

    tmp_db =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-bin-wrapper-#{System.unique_integer([:positive])}.db"
      )

    # Checkpoint the WAL into the main DB file so the copy is self-contained,
    # then copy the main file (schema is committed data, independent of any
    # open sandbox transaction).
    Sandbox.unboxed_run(Repo, fn -> Repo.query!("PRAGMA wal_checkpoint(TRUNCATE)") end)
    File.cp!(source_db, tmp_db)

    on_exit(fn ->
      File.rm(tmp_db)
      File.rm(tmp_db <> "-wal")
      File.rm(tmp_db <> "-shm")
    end)

    env = [
      {"CK_PROJECT_ROOT", File.cwd!()},
      {"CK_CLI_MODE", "1"},
      {"LOGGER_LEVEL", "error"},
      {"CK_TEST_DB", tmp_db}
    ]

    %{env: env}
  end

  test "bin/controlkeel context --json emits parseable JSON on stdout", %{env: env} do
    {output, 0} = System.cmd(@wrapper, ["context", "--session-id", "1", "--json"], env: env)

    assert output != ""
    assert {:ok, payload} = Jason.decode(output)
    assert is_map(payload)
    assert Map.has_key?(payload, "session_id")
  end

  test "bin/controlkeel validate --json emits parseable JSON on stdout", %{env: env} do
    {output, 0} =
      System.cmd(@wrapper, ["validate", "--content", "echo hello", "--kind", "shell", "--json"],
        env: env
      )

    assert output != ""
    assert {:ok, payload} = Jason.decode(output)
    assert is_map(payload)
    assert Map.has_key?(payload, "decision")
  end

  test "--format only enables JSON mode for a json value" do
    wrapper = File.read!(@wrapper)

    assert wrapper =~ "--json|--format=json|--format=JSON)"
    assert wrapper =~ ~s(if [ "$arg" = "--format" ])
    assert wrapper =~ "json|JSON) return 0"
    refute wrapper =~ "--json|--format)"
  end
end
