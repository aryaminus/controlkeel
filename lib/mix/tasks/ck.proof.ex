defmodule Mix.Tasks.Ck.Proof do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "Show a proof bundle by proof id or task id"

  def run([id]) do
    Mix.Task.run("app.start")

    with {:ok, parsed} <- CLI.parse(["proof", id]),
         {:ok, lines} <- CLI.run_command(parsed, File.cwd!()) do
      Enum.each(lines, fn line -> Mix.shell().info(line) end)
    else
      {:error, message} -> Mix.raise(message)
    end
  end

  def run(_args), do: Mix.raise("Usage: mix ck.proof <proof-id|task-id>")
end
