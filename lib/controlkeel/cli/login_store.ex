defmodule ControlKeel.CLI.LoginStore do
  @moduledoc """
  Local storage for the CLI's user access token.

  The token is written to `~/.controlkeel/login.json` with mode `0600`. If the
  chmod fails we refuse to persist rather than silently writing a
  world-readable bearer credential — a token file that other local users can
  read is a credential leak, so failing loudly is safer than failing open.
  """

  @filename "login.json"

  def path do
    Path.join([dir(), @filename])
  end

  def dir do
    case System.get_env("CONTROLKEEL_HOME") do
      nil -> Path.join(System.user_home!(), ".controlkeel")
      "" -> Path.join(System.user_home!(), ".controlkeel")
      dir -> dir
    end
  end

  @doc "Store `{access_token, server, email}` securely (0600)."
  def save(attrs) when is_map(attrs) do
    with :ok <- File.mkdir_p(dir()),
         :ok <- File.write(path(), Jason.encode!(attrs)),
         :ok <- secure_permissions() do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Read the stored login, or `:error` if absent/corrupt."
  def load do
    case File.read(path()) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{"access_token" => _token} = attrs} -> {:ok, attrs}
          _ -> :error
        end

      {:error, _} ->
        :error
    end
  end

  def delete do
    case File.rm(path()) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp secure_permissions do
    case File.chmod(path(), 0o600) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
