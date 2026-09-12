defmodule Mix.Tasks.Ck.Proofs do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "List proof bundles for the current governed session"

  def run(args) do
    ControlKeel.Runtime.Defaults.bind_inspection_database()
    Mix.Task.run("app.start")

    with {:ok, parsed} <- CLI.parse(["proofs" | args]),
         {:ok, lines} <- CLI.run_command(parsed, ControlKeel.Project.Root.resolve(File.cwd!())) do
      Enum.each(lines, fn line -> Mix.shell().info(line) end)
    else
      {:error, message} -> Mix.raise(message)
    end
  end
end
