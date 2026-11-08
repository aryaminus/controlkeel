defmodule ControlKeel.BinWrapperTest do
  use ExUnit.Case, async: false

  # The wrapper subprocess is isolated by a SQLite snapshot. The shell script
  # itself is adapter-agnostic.
  @moduletag :sqlite_only

  alias ControlKeel.Repo.Local
  alias Ecto.Adapters.SQL.Sandbox

  @wrapper Path.expand("../../bin/controlkeel", __DIR__)

  # The wrapper runs as a subprocess, so its writes must stay outside the
  # shared sandbox. VACUUM INTO creates a consistent SQLite snapshot while
  # other tests write, unlike checkpointing and copying the shared DB file.
  setup do
    tmp_db =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-bin-wrapper-#{System.unique_integer([:positive])}.db"
      )

    escaped_tmp_db = String.replace(tmp_db, "'", "''")

    Sandbox.unboxed_run(Local, fn ->
      Local.query!("VACUUM INTO '#{escaped_tmp_db}'")
    end)

    on_exit(fn ->
      File.rm(tmp_db)
      File.rm(tmp_db <> "-wal")
      File.rm(tmp_db <> "-shm")
    end)

    env = [
      {"CK_PROJECT_ROOT", File.cwd!()},
      {"CK_CLI_MODE", "1"},
      {"LOGGER_LEVEL", "error"},
      {"DATABASE_PATH", tmp_db},
      {"CK_TEST_DB", tmp_db},
      {"CK_TEST_SUBPROCESS", "1"}
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

  test "bin/controlkeel context --json bootstraps an empty SQLite database" do
    tmp_db =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-bin-wrapper-fresh-#{System.unique_integer([:positive])}.db"
      )

    on_exit(fn ->
      File.rm(tmp_db)
      File.rm(tmp_db <> "-wal")
      File.rm(tmp_db <> "-shm")
    end)

    env = [
      {"CK_PROJECT_ROOT", File.cwd!()},
      {"LOGGER_LEVEL", "error"},
      {"DATABASE_PATH", tmp_db},
      {"CK_TEST_DB", tmp_db},
      {"CK_TEST_SUBPROCESS", "1"}
    ]

    {output, 0} = System.cmd(@wrapper, ["context", "--session-id", "1", "--json"], env: env)

    assert {:ok, payload} = Jason.decode(output)
    assert is_map(payload)
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
