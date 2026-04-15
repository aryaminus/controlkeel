defmodule Mix.Tasks.Ck.Mcp do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "Runs the ControlKeel MCP server over stdio"

  @impl true
  def run(args) do
    # Ensure dev endpoint asset watchers stay off (see config/runtime.exs CK_MCP_MODE).
    System.put_env("CK_MCP_MODE", "1")
    # Keep Mix.info / compile notices off stdout; MCP owns that pipe for JSON-RPC frames.
    Mix.shell(Mix.Shell.Quiet)

    Mix.Task.run("app.start")

    parsed = parse!(["mcp" | args])

    case CLI.run_command(parsed, File.cwd!()) do
      :ok ->
        :ok

      {:ok, lines} ->
        Enum.each(lines, fn line -> Mix.shell().info(line) end)

      {:error, message} ->
        Mix.raise(message)
    end
  end

  defp parse!(argv) do
    case CLI.parse(argv) do
      {:ok, parsed} -> parsed
      {:error, message} -> Mix.raise(message)
    end
  end
end
