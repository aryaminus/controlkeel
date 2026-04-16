defmodule ControlKeel.ClaudeCLI do
  @moduledoc false

  def attach_local(project_root, command, args \\ [], server_name \\ "controlkeel") do
    config = %{
      "type" => "stdio",
      "command" => command,
      "args" => args
    }

    with :ok <- ensure_available(),
         :ok <-
           ensure_server_registered(project_root, server_name, config),
         {:ok, output} <- run(["mcp", "get", server_name], cd: project_root),
         :ok <- verify_get_output(output, server_name, command) do
      {:ok,
       %{
         "server_name" => server_name,
         "scope" => "local",
         "command" => command,
         "args" => args,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  defp ensure_server_registered(project_root, server_name, config) do
    case run(["mcp", "add-json", server_name, Jason.encode!(config), "--scope", "local"],
           cd: project_root
         ) do
      {:ok, _output} ->
        :ok

      {:error, output} when is_binary(output) ->
        if already_exists_error?(output) do
          :ok
        else
          {:error, output}
        end

      other ->
        other
    end
  end

  defp already_exists_error?(output) do
    normalized = String.downcase(output)
    String.contains?(normalized, "already exists") and String.contains?(normalized, "mcp")
  end

  defp ensure_available do
    executable = executable()

    cond do
      Path.type(executable) == :absolute and File.exists?(executable) ->
        :ok

      is_binary(System.find_executable(executable)) ->
        :ok

      true ->
        {:error,
         "Claude Code CLI was not found. Install `claude` and retry `mix ck.attach claude-code`."}
    end
  end

  defp run(args, opts) do
    case System.cmd(executable(), args,
           stderr_to_stdout: true,
           into: "",
           cd: Keyword.fetch!(opts, :cd)
         ) do
      {output, 0} ->
        {:ok, output}

      {output, _code} ->
        if String.contains?(String.downcase(output), "add-json") or
             String.contains?(String.downcase(output), "unknown") do
          {:error,
           "Your Claude CLI does not support `mcp add-json`. Upgrade Claude Code and retry."}
        else
          {:error, String.trim(output)}
        end
    end
  end

  defp verify_get_output(output, server_name, command_path) do
    normalized = String.downcase(output)

    cond do
      String.contains?(normalized, String.downcase(server_name)) and
          String.contains?(output, command_path) ->
        :ok

      String.contains?(normalized, String.downcase(server_name)) ->
        :ok

      true ->
        {:error,
         "Claude CLI registration did not verify cleanly. Run `claude mcp get #{server_name}` and confirm the server is present."}
    end
  end

  defp executable do
    System.get_env("CONTROLKEEL_CLAUDE_BIN") || "claude"
  end
end
