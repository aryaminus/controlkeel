defmodule ControlKeel.Runtime.DefaultsTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Runtime.Defaults

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
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-cwd-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    with_envs(
      %{"DATABASE_PATH" => nil, "CK_PROJECT_ROOT" => nil, "CONTROLKEEL_HOME" => tmp_home},
      fn ->
        File.cd!(tmp_dir, fn ->
          path = Defaults.database_path()

          refute String.starts_with?(path, tmp_dir)
          assert String.ends_with?(path, "controlkeel.db")
          assert File.dir?(Path.dirname(path))
        end)
      end
    )
  end

  test "database_path prefers a project-local sqlite db when inside a repo", %{tmp_home: tmp_home} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-project-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "lib/trial"))
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Trial.MixProject do\nend\n")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    with_envs(
      %{"DATABASE_PATH" => nil, "CK_PROJECT_ROOT" => nil, "CONTROLKEEL_HOME" => tmp_home},
      fn ->
        File.cd!(tmp_dir, fn ->
          path = Defaults.database_path()

          assert path == Path.join([File.cwd!(), "controlkeel", "controlkeel.db"])
        end)
      end
    )
  end

  test "CK_PROJECT_ROOT selects the governed project's database over the working directory",
       %{tmp_home: tmp_home} do
    project =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-governed-#{System.unique_integer([:positive])}"
      )

    elsewhere = Path.join(tmp_home, "elsewhere")

    File.rm_rf!(project)
    File.mkdir_p!(Path.join(project, "lib/trial"))
    # macOS tmp lives under a /var -> /private/var symlink; root resolution
    # returns the real path, so compare against that.
    project = File.cd!(project, fn -> File.cwd!() end)
    File.write!(Path.join(project, "mix.exs"), "defmodule Trial.MixProject do\nend\n")
    File.mkdir_p!(elsewhere)
    on_exit(fn -> File.rm_rf!(project) end)

    with_envs(
      %{"DATABASE_PATH" => nil, "CK_PROJECT_ROOT" => project, "CONTROLKEEL_HOME" => tmp_home},
      fn ->
        File.cd!(elsewhere, fn ->
          assert Defaults.governed_root() == project

          assert Defaults.database_path() ==
                   Path.join([project, "controlkeel", "controlkeel.db"])
        end)
      end
    )
  end

  test "separate projects do not inherit the legacy database", %{tmp_home: tmp_home} do
    with_envs(
      %{"DATABASE_PATH" => nil, "CK_PROJECT_ROOT" => nil, "CONTROLKEEL_HOME" => tmp_home},
      fn ->
        global = Defaults.global_database_path()
        File.write!(global, "legacy data")

        for name <- ["first-project", "second-project"] do
          root = Path.join(tmp_home, name)
          File.mkdir_p!(root)
          File.write!(Path.join(root, "package.json"), "{}")

          File.cd!(root, fn ->
            path = Defaults.database_path()
            assert path == Path.join([File.cwd!(), "controlkeel", "controlkeel.db"])
            refute File.exists?(path)
          end)
        end

        assert File.read!(global) == "legacy data"
      end
    )
  end

  test "prod runtime config does not copy the legacy database into a new project",
       %{tmp_home: tmp_home} do
    root = Path.join(tmp_home, "fresh-project")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "package.json"), "{}")

    with_envs(
      %{
        "DATABASE_PATH" => nil,
        "DATABASE_URL" => nil,
        "CONTROLKEEL_RUNTIME_MODE" => nil,
        "CONTROLKEEL_HOME" => tmp_home,
        "SECRET_KEY_BASE" => String.duplicate("k", 64)
      },
      fn ->
        global = Defaults.global_database_path()

        for suffix <- ["", "-wal", "-shm"] do
          File.write!(global <> suffix, "legacy data")
        end

        runtime_config = Path.expand("../../../config/runtime.exs", __DIR__)

        File.cd!(root, fn ->
          config = Config.Reader.read!(runtime_config, env: :prod)
          db_path = get_in(config, [:controlkeel, ControlKeel.Repo.Local, :database])
          project_db = Path.join([File.cwd!(), "controlkeel", "controlkeel.db"])

          assert db_path == project_db

          for suffix <- ["", "-wal", "-shm"] do
            refute File.exists?(project_db <> suffix)
          end
        end)

        assert File.read!(global) == "legacy data"
      end
    )
  end

  test "secret_key_base is generated once and then reused", %{tmp_home: tmp_home} do
    with_envs(%{"SECRET_KEY_BASE" => nil, "HOME" => tmp_home}, fn ->
      first = Defaults.secret_key_base()
      second = Defaults.secret_key_base()

      assert first == second
      assert byte_size(first) > 40
    end)
  end

  test "endpoint_url_config defaults to local values" do
    with_envs(
      %{
        "CONTROLKEEL_RUNTIME_MODE" => nil,
        "PHX_HOST" => nil,
        "PHX_URL_SCHEME" => nil,
        "PHX_URL_PORT" => nil
      },
      fn ->
        assert Defaults.endpoint_url_config() ==
                 [host: "localhost", scheme: "http", port: 4000]
      end
    )
  end

  test "endpoint_url_config defaults to cloud values" do
    with_envs(
      %{
        "CONTROLKEEL_RUNTIME_MODE" => "cloud",
        "PHX_HOST" => nil,
        "PHX_URL_SCHEME" => nil,
        "PHX_URL_PORT" => nil
      },
      fn ->
        assert Defaults.endpoint_url_config() ==
                 [host: "controlkeel.com", scheme: "https", port: 443]
      end
    )
  end

  test "endpoint_url_config applies host, scheme, and port overrides" do
    with_envs(
      %{
        "CONTROLKEEL_RUNTIME_MODE" => "local",
        "PHX_HOST" => "example.test",
        "PHX_URL_SCHEME" => "https",
        "PHX_URL_PORT" => "8443"
      },
      fn ->
        assert Defaults.endpoint_url_config() ==
                 [host: "example.test", scheme: "https", port: 8443]
      end
    )
  end

  test "endpoint_url_config falls back when PHX_URL_PORT is invalid" do
    with_envs(
      %{
        "CONTROLKEEL_RUNTIME_MODE" => "cloud",
        "PHX_HOST" => nil,
        "PHX_URL_SCHEME" => nil,
        "PHX_URL_PORT" => "not-a-number"
      },
      fn ->
        assert Defaults.endpoint_url_config() ==
                 [host: "controlkeel.com", scheme: "https", port: 443]
      end
    )

    with_envs(
      %{
        "CONTROLKEEL_RUNTIME_MODE" => "local",
        "PHX_HOST" => nil,
        "PHX_URL_SCHEME" => nil,
        "PHX_URL_PORT" => "0"
      },
      fn ->
        assert Defaults.endpoint_url_config() ==
                 [host: "localhost", scheme: "http", port: 4000]
      end
    )
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

  describe "bind_inspection_database/0" do
    setup do
      prev_repo = Application.get_env(:controlkeel, ControlKeel.Repo.Local, [])

      on_exit(fn ->
        Application.put_env(:controlkeel, ControlKeel.Repo.Local, prev_repo)
      end)
    end

    test "redirects Repo to the resolved project database when it exists" do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "controlkeel-bind-inspection-#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(tmp)
      File.mkdir_p!(Path.join(tmp, "controlkeel"))
      on_exit(fn -> File.rm_rf!(tmp) end)

      db_path = Path.join([tmp, "controlkeel", "controlkeel.db"])
      # The redirect requires the resolved DB file to exist.
      File.write!(db_path, "stub")

      # Point DATABASE_PATH at our temp DB so database_path/0 resolves to it.
      Application.put_env(:controlkeel, ControlKeel.Repo.Local, database: "/dev/null/original.db")

      with_envs(%{"DATABASE_PATH" => db_path}, fn ->
        result = Defaults.bind_inspection_database()

        # Inside `mix test` the app is already started, so the pool can't be
        # rebound — the function reports that. Either outcome means the config
        # was updated to the governed path.
        redirected_path =
          case result do
            {:redirected, p} -> p
            {:repo_already_started, p} -> p
          end

        assert redirected_path == db_path

        redirected = Application.get_env(:controlkeel, ControlKeel.Repo.Local, [])
        assert Keyword.get(redirected, :database) == db_path
      end)
    end

    test "is a no-op when the resolved database does not exist yet" do
      Application.put_env(:controlkeel, ControlKeel.Repo.Local, database: "/dev/null/original.db")

      with_envs(%{"DATABASE_PATH" => "/nonexistent/path/controlkeel.db"}, fn ->
        assert :noop = Defaults.bind_inspection_database()

        assert Keyword.get(
                 Application.get_env(:controlkeel, ControlKeel.Repo.Local, []),
                 :database
               ) ==
                 "/dev/null/original.db"
      end)
    end

    test "is a no-op when the resolved path already matches the configured one" do
      db = "/dev/null/already-bound.db"
      Application.put_env(:controlkeel, ControlKeel.Repo.Local, database: db)

      with_envs(%{"DATABASE_PATH" => db}, fn ->
        assert :noop = Defaults.bind_inspection_database()
      end)
    end
  end
end
