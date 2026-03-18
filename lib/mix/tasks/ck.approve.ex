defmodule Mix.Tasks.Ck.Approve do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "Approves a finding in the current governed session"

  @impl true
  def run([finding_id]) do
    Mix.Task.run("app.start")

    parsed = parse!(["approve", finding_id])

    case CLI.run_command(parsed, File.cwd!()) do
      {:ok, lines} ->
        Enum.each(lines, fn line -> Mix.shell().info(line) end)

      {:error, message} ->
        Mix.raise(message)
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix ck.approve <finding-id>")
  end

  defp parse!(argv) do
    case CLI.parse(argv) do
      {:ok, parsed} -> parsed
      {:error, message} -> Mix.raise(message)
    end
  end
end
