defmodule Mix.Tasks.Ck.Memory.Search do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "Search typed memory for the current governed session"

  def run([query | rest]) do
    Mix.Task.run("app.start")

    with {:ok, parsed} <- CLI.parse(["memory", "search", query | rest]),
         {:ok, lines} <- CLI.run_command(parsed, File.cwd!()) do
      Enum.each(lines, fn line -> Mix.shell().info(line) end)
    else
      {:error, message} -> Mix.raise(message)
    end
  end

  def run(_args),
    do:
      Mix.raise("Usage: mix ck.memory.search <query> [--session-id <id>] [--type <record-type>]")
end
