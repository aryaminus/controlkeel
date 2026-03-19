defmodule Mix.Tasks.Ck.Policy do
  use Mix.Task

  @shortdoc "Manage learned policy artifacts"

  alias ControlKeel.CLI

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    with {:ok, parsed} <- CLI.parse(["policy" | args]),
         {:ok, lines} <- CLI.run_command(parsed, File.cwd!()) do
      Enum.each(lines, fn line -> Mix.shell().info(line) end)
    else
      {:error, message} ->
        Mix.raise(message)
    end
  end
end
