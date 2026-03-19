defmodule ControlKeel.EntryPoint do
  @moduledoc false

  use Application

  alias ControlKeel.CLI

  @impl true
  def start(_type, _args) do
    if standalone_runtime?() do
      start_standalone()
    else
      ControlKeel.Application.start_link()
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    ControlKeel.Application.config_change(changed, nil, removed)
  end

  defp start_standalone do
    case CLI.parse(CLI.standalone_argv()) do
      {:ok, parsed} ->
        if CLI.app_required?(parsed) do
          maybe_enable_server(parsed)

          with {:ok, supervisor} <- ControlKeel.Application.start_link() do
            if CLI.server_mode?(parsed) do
              {:ok, supervisor}
            else
              Task.start(fn ->
                run_and_halt(parsed)
              end)

              {:ok, supervisor}
            end
          end
        else
          run_and_halt(parsed)
          {:ok, self()}
        end

      {:error, message} ->
        run_help_and_halt(message)
        {:ok, self()}
    end
  end

  defp maybe_enable_server(parsed) do
    endpoint_config = Application.get_env(:controlkeel, ControlKeelWeb.Endpoint, [])

    Application.put_env(
      :controlkeel,
      ControlKeelWeb.Endpoint,
      Keyword.put(endpoint_config, :server, CLI.server_mode?(parsed))
    )
  end

  def standalone_runtime? do
    cond do
      System.get_env("__BURRITO") not in [nil, ""] ->
        true

      Code.ensure_loaded?(Burrito.Util) and
          function_exported?(Burrito.Util, :running_standalone?, 0) ->
        Burrito.Util.running_standalone?()

      true ->
        not Code.ensure_loaded?(Mix)
    end
  end

  defp run_and_halt(parsed) do
    parsed
    |> CLI.execute()
    |> halt_vm()
  end

  defp run_help_and_halt(message) do
    CLI.execute(%{command: :help, options: %{}, args: []})
    IO.puts(:stderr, message)
    halt_vm(1)
  end

  defp halt_vm(exit_code) do
    halt_fun().(exit_code)
  end

  defp halt_fun do
    Application.get_env(:controlkeel, :entry_point_halt_fun, &System.halt/1)
  end
end
