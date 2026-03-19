defmodule Mix.Tasks.Ck.Benchmark do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "List, run, import, and export benchmark runs"

  def run(args) do
    Mix.Task.run("app.start")

    with {:ok, parsed} <- CLI.parse(["benchmark" | args]),
         {:ok, lines} <- CLI.run_command(parsed, File.cwd!()) do
      Enum.each(lines, fn line -> Mix.shell().info(line) end)
    else
      {:error, message} -> Mix.raise(message)
    end
  end
end
