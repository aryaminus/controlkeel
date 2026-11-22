defmodule ControlKeel.Runtime.Defaults do
  @moduledoc false

  @app_dir_name "controlkeel"
  @secret_file_name "secret_key_base"

  def app_data_dir do
    path =
      case :os.type() do
        {:win32, _} ->
          Path.join(System.get_env("LOCALAPPDATA") || default_home(), "ControlKeel")

        {:unix, :darwin} ->
          Path.join([default_home(), "Library", "Application Support", "ControlKeel"])

        _ ->
          Path.join(
            System.get_env("XDG_DATA_HOME") || Path.join(default_home(), ".local/share"),
            @app_dir_name
          )
      end

    ensure_dir!(path)
  end

  def database_path do
    System.get_env("DATABASE_PATH") ||
      project_database_path(File.cwd!()) ||
      global_database_path()
  end

  @doc """
  Reconfigures `ControlKeel.Repo.Local` to point at the resolved project/runtime
  database, so inspection tooling (`mix ck.findings`, `ck.context`, …) reads the
  SAME database the MCP server governs and the commit gate gates on.

  Local-mode only. In cloud mode the dispatcher routes reads to
  `ControlKeel.CloudRepo` and there is no local SQLite file to bind.

  Must be called BEFORE `Mix.Task.run("app.start")` so the Repo pool opens
  against the governed database. No-op when the configured database already
  matches, when no project database resolves, or when the resolved file does
  not exist yet (e.g. a fresh project that has never been run by the MCP server).

  Returns `{:redirected, path}`, `:noop`, or
  `{:repo_already_started, path}`.
  """
  def bind_inspection_database do
    resolved = database_path()

    current = Application.get_env(:controlkeel, ControlKeel.Repo.Local, [])
    current_path = Keyword.get(current, :database)

    cond do
      resolved in [nil, ""] ->
        :noop

      resolved == current_path ->
        :noop

      not File.exists?(resolved) ->
        # The governed database doesn't exist yet — inspection can't read it and
        # must not create an empty file the MCP server would later have to adopt.
        :noop

      true ->
        # Preserve the rest of the Repo config (pool_size, journal_mode, …) and
        # only swap the database path.
        Application.put_env(
          :controlkeel,
          ControlKeel.Repo.Local,
          Keyword.put(current, :database, resolved)
        )

        if app_started?() do
          # Pool already connected to the dev database; the redirect won't take
          # effect until restart. Surface it so the caller can warn.
          {:repo_already_started, resolved}
        else
          {:redirected, resolved}
        end
    end
  end

  defp app_started? do
    Application.started_applications()
    |> Enum.any?(&match?({:controlkeel, _, _}, &1))
  end

  @doc """
  Path to the legacy global database under the OS app-data directory. This was
  the only database location before the project-local pivot, so it is the source
  we migrate from for upgrading users.
  """
  def global_database_path do
    Path.join(app_data_dir(), "controlkeel.db")
  end

  def secret_key_base do
    System.get_env("SECRET_KEY_BASE") || read_or_create_secret()
  end

  def endpoint_url_config do
    runtime_mode = runtime_mode()
    {default_host, default_scheme, default_port} = endpoint_defaults(runtime_mode)

    [
      host: env_or_default("PHX_HOST", default_host),
      scheme: env_or_default("PHX_URL_SCHEME", default_scheme),
      port: endpoint_port(default_port)
    ]
  end

  defp read_or_create_secret do
    path = Path.join(app_data_dir(), @secret_file_name)

    case File.read(path) do
      {:ok, secret} ->
        String.trim(secret)

      {:error, :enoent} ->
        secret = generate_secret()
        File.write!(path, secret <> "\n")
        secret
    end
  end

  defp generate_secret do
    64
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp runtime_mode do
    ControlKeel.Runtime.Mode.current()
  end

  defp endpoint_defaults(:cloud), do: {"controlkeel.com", "https", 443}
  defp endpoint_defaults(:self_hosted), do: {"localhost", "https", 443}
  defp endpoint_defaults(:local), do: {"localhost", "http", 4000}

  defp env_or_default(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      value -> value
    end
  end

  defp endpoint_port(default_port) do
    case System.get_env("PHX_URL_PORT") do
      nil -> default_port
      "" -> default_port
      value -> parse_positive_integer(value, default_port)
    end
  end

  defp parse_positive_integer(value, fallback) do
    case Integer.parse(value) do
      {port, ""} when port > 0 -> port
      _ -> fallback
    end
  end

  # CONTROLKEEL_HOME relocates the app-data root and is read at runtime (unlike
  # OS HOME, which OTP caches at VM boot). Honoring it keeps the data directory
  # overridable in production and lets tests redirect app-data writes without
  # touching the real user home. Same convention used by ck_token_audit.
  defp default_home do
    case System.get_env("CONTROLKEEL_HOME") do
      home when is_binary(home) and home != "" -> home
      _ -> System.user_home!()
    end
  end

  defp project_database_path(cwd) do
    root = ControlKeel.Project.Root.resolve(cwd)

    if ControlKeel.Project.Root.project_root?(root) do
      Path.join([root, "controlkeel", "controlkeel.db"])
    end
  end

  defp ensure_dir!(path) do
    File.mkdir_p!(path)
    path
  end
end
