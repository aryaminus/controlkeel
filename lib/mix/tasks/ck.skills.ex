defmodule Mix.Tasks.Ck.Skills do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "List, validate, export, install, and diagnose ControlKeel skills"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    with {:ok, parsed} <- CLI.parse(["skills" | args]),
         {:ok, lines} <- CLI.run_command(parsed, File.cwd!()) do
      Enum.each(lines, fn line -> Mix.shell().info(line) end)
    else
      {:error, message} -> Mix.raise(message)
    end
  end
end
