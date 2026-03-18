defmodule Mix.Tasks.Ck.Status do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "Shows the current governed session status"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    parsed = parse!(["status"])

    case CLI.run_command(parsed, File.cwd!()) do
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
