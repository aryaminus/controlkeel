defmodule Mix.Tasks.Ck.Mcp do
  use Mix.Task

  alias ControlKeel.CLI

  @shortdoc "Runs the ControlKeel MCP server over stdio"

  @impl true
  def run(args) do
    # Ensure dev endpoint asset watchers stay off (see config/runtime.exs CK_MCP_MODE).
    System.put_env("CK_MCP_MODE", "1")
    # Keep Mix.info / compile notices off stdout; MCP owns that pipe for JSON-RPC frames.
    Mix.shell(Mix.Shell.Quiet)

    mcp_boot_log("[controlkeel-mcp] starting (CK_PROJECT_ROOT=#{inspect(System.get_env("CK_PROJECT_ROOT"))})")

    t0 = System.monotonic_time(:millisecond)
    Mix.Task.run("app.start", app_start_cli_args())
    dt = System.monotonic_time(:millisecond) - t0
    mcp_boot_log("[controlkeel-mcp] app.start finished in #{dt}ms")

    parsed = parse!(["mcp" | args])

    case CLI.run_command(parsed, File.cwd!()) do
      :ok ->
        :ok

      {:ok, lines} ->
        Enum.each(lines, fn line -> Mix.shell().info(line) end)

      {:error, message} ->
        Mix.raise(message)
    end
  end

  defp parse!(argv) do
    case CLI.parse(argv) do
      {:ok, parsed} -> parsed
      {:error, message} -> Mix.raise(message)
    end
  end

  # Passes through to app.config → compile. Skips a redundant compile pass when
  # sources are unchanged (helps Cursor stay under connect timeouts). Set
  # CK_MCP_FORCE_COMPILE=1 to disable.
  defp app_start_cli_args do
    if System.get_env("CK_MCP_FORCE_COMPILE") in ~w(1 true TRUE yes YES) do
      []
    else
      ["--no-compile"]
    end
  end

  defp mcp_boot_log(line) do
    # Stderr only — stdout must stay JSON-RPC clean after the MCP reader starts.
    IO.puts(:stderr, line)
  end
end
