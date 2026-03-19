defmodule Mix.Tasks.Ck.Pause do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "Pause a task and capture a resume packet"

  def run([task_id]) do
    Mix.Task.run("app.start")

    with {:ok, parsed} <- CLI.parse(["pause", task_id]),
         {:ok, lines} <- CLI.run_command(parsed, File.cwd!()) do
      Enum.each(lines, fn line -> Mix.shell().info(line) end)
    else
      {:error, message} -> Mix.raise(message)
    end
  end

  def run(_args), do: Mix.raise("Usage: mix ck.pause <task-id>")
end
