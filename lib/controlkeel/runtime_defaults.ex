defmodule ControlKeel.RuntimeDefaults do
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
    System.get_env("DATABASE_PATH") || Path.join(app_data_dir(), "controlkeel.db")
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
    case System.get_env("CONTROLKEEL_RUNTIME_MODE", "local") do
      "cloud" -> :cloud
      _ -> :local
    end
  end

  defp endpoint_defaults(:cloud), do: {"controlkeel.com", "https", 443}
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

  defp default_home do
    System.user_home!()
  end

  defp ensure_dir!(path) do
    File.mkdir_p!(path)
    path
  end
end
