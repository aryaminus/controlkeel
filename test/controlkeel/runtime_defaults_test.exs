defmodule ControlKeel.RuntimeDefaultsTest do
  use ExUnit.Case, async: false

  alias ControlKeel.RuntimeDefaults

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_home)
    File.mkdir_p!(tmp_home)
    on_exit(fn -> File.rm_rf!(tmp_home) end)

    {:ok, tmp_home: tmp_home}
  end

  test "database_path falls back to a local app-data directory", %{tmp_home: tmp_home} do
    with_envs(%{"DATABASE_PATH" => nil, "HOME" => tmp_home}, fn ->
      path = RuntimeDefaults.database_path()

      assert String.ends_with?(path, "controlkeel.db")
      assert File.dir?(Path.dirname(path))
    end)
  end

  test "secret_key_base is generated once and then reused", %{tmp_home: tmp_home} do
    with_envs(%{"SECRET_KEY_BASE" => nil, "HOME" => tmp_home}, fn ->
      first = RuntimeDefaults.secret_key_base()
      second = RuntimeDefaults.secret_key_base()

      assert first == second
      assert byte_size(first) > 40
    end)
  end

  defp with_envs(changes, fun) do
    previous =
      Enum.into(changes, %{}, fn {key, _value} -> {key, System.get_env(key)} end)

    try do
      Enum.each(changes, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
