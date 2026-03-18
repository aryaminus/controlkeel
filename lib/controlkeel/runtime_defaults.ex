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

  defp default_home do
    System.user_home!()
  end

  defp ensure_dir!(path) do
    File.mkdir_p!(path)
    path
  end
end
