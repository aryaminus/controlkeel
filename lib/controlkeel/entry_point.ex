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
                exit_code = CLI.execute(parsed)
                System.halt(exit_code)
              end)

              {:ok, supervisor}
            end
          end
        else
          Task.start_link(fn ->
            exit_code = CLI.execute(parsed)
            System.halt(exit_code)
          end)
        end

      {:error, message} ->
        Task.start_link(fn ->
          CLI.execute(%{command: :help, options: %{}, args: []})
          IO.puts(:stderr, message)
          System.halt(1)
        end)
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
      Code.ensure_loaded?(Burrito.Util) and
          function_exported?(Burrito.Util, :running_standalone?, 0) ->
        Burrito.Util.running_standalone?()

      true ->
        not Code.ensure_loaded?(Mix)
    end
  end
end
