defmodule Mix.Tasks.Ck.Context do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "Shows the current governed session context"

  @impl true
  def run(args) do
    previous_level = Logger.level()
    quiet_json? = json_args?(args)

    try do
      if quiet_json?, do: Logger.configure(level: :warning)

      ControlKeel.Runtime.Defaults.bind_inspection_database()
      Mix.Task.run("app.start")
      if quiet_json?, do: Logger.configure(level: :warning)

      parsed = parse!(["context" | args])

      case CLI.run_command(parsed, ControlKeel.Project.Root.resolve(File.cwd!())) do
        {:ok, lines} ->
          emit_lines(lines, quiet_json?)

        {:error, message} ->
          Mix.raise(message)
      end
    after
      if quiet_json?, do: Logger.configure(level: previous_level)
    end
  end

  defp emit_lines(lines, true = _quiet_json?) do
    Enum.each(lines, fn line -> IO.puts(line) end)
  end

  defp emit_lines(lines, false = _quiet_json?) do
    Enum.each(lines, fn line -> Mix.shell().info(line) end)
  end

  defp json_args?(args) do
    "--json" in args or
      Enum.chunk_every(args, 2, 1, :discard) |> Enum.any?(&(&1 == ["--format", "json"]))
  end

  defp parse!(argv) do
    case CLI.parse(argv) do
      {:ok, parsed} -> parsed
      {:error, message} -> Mix.raise(message)
    end
  end
end
