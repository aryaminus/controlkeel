defmodule Mix.Tasks.Ck.Resume do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "Resume a paused or blocked task"

  def run([task_id]) do
    ControlKeel.Runtime.Defaults.bind_inspection_database()
    Mix.Task.run("app.start")

    with {:ok, parsed} <- CLI.parse(["resume", task_id]),
         {:ok, lines} <- CLI.run_command(parsed, ControlKeel.Project.Root.resolve(File.cwd!())) do
      Enum.each(lines, fn line -> Mix.shell().info(line) end)
    else
      {:error, message} -> Mix.raise(message)
    end
  end

  def run(_args), do: Mix.raise("Usage: mix ck.resume <task-id>")
end
