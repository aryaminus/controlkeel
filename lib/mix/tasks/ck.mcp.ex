defmodule Mix.Tasks.Ck.Mcp do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "Runs the ControlKeel MCP server over stdio"

  @impl true
  def run(args) do
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
