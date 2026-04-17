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
        ensure_standalone_logger_stderr()
        maybe_prepare_stdio_mcp!(parsed)
        maybe_prepare_machine_output!(parsed)

        if CLI.app_required?(parsed) do
          maybe_enable_server(parsed)

          with {:ok, supervisor} <- application_start_fun().() do
            if CLI.server_mode?(parsed) do
              {:ok, supervisor}
            else
              run_and_halt(parsed)
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

  defp maybe_prepare_stdio_mcp!(%{command: :mcp}) do
    # Release boot evaluates config/runtime.exs before this callback; ensure MCP
    # mode is visible to Application and mirror runtime.exs endpoint safeguards.
    System.put_env("CK_MCP_MODE", "1")

    endpoint_config = Application.get_env(:controlkeel, ControlKeelWeb.Endpoint, [])

    Application.put_env(
      :controlkeel,
      ControlKeelWeb.Endpoint,
      endpoint_config
      |> Keyword.put(:watchers, [])
      |> Keyword.put(:server, false)
      |> Keyword.put(:code_reloader, false)
    )

    # Repo SQL and Logger default to noisy stdout in dev; stdio MCP must keep
    # stdout JSON-only (see config/runtime.exs CK_MCP_MODE).
    repo_cfg = Application.get_env(:controlkeel, ControlKeel.Repo) || []

    Application.put_env(
      :controlkeel,
      ControlKeel.Repo,
      Keyword.put(repo_cfg, :log, false)
    )

    cloud_cfg = Application.get_env(:controlkeel, ControlKeel.CloudRepo) || []

    Application.put_env(
      :controlkeel,
      ControlKeel.CloudRepo,
      Keyword.put(cloud_cfg, :log, false)
    )

    if System.get_env("LOGGER_LEVEL") in [nil, ""] do
      Application.put_env(:logger, :level, :warning)
    end
  end

  defp maybe_prepare_stdio_mcp!(_parsed), do: :ok

  defp maybe_prepare_machine_output!(parsed) do
    if System.get_env("LOGGER_LEVEL") in [nil, ""] and machine_output?(parsed) do
      Application.put_env(:logger, :level, :warning)
    end
  end

  defp machine_output?(%{options: options}) do
    json? = option_value(options, :json) == true
    format = option_value(options, :format)

    json? or format in ["json", :json]
  end

  defp machine_output?(_parsed), do: false

  defp option_value(options, key) when is_list(options), do: Keyword.get(options, key)
  defp option_value(options, key) when is_map(options), do: Map.get(options, key)
  defp option_value(_options, _key), do: nil

  defp ensure_standalone_logger_stderr do
    case :logger.get_handler_config(:default) do
      {:ok, %{module: :logger_std_h} = handler} ->
        current_type = handler.config |> Kernel.||(%{}) |> Map.get(:type)

        if current_type == :standard_error do
          :ok
        else
          replacement = %{
            handler
            | config: Map.put(handler.config || %{}, :type, :standard_error)
          }

          with :ok <- :logger.remove_handler(:default),
               {:ok, _handler_id} <- :logger.add_handler(:default, :logger_std_h, replacement) do
            :ok
          else
            _ -> :ok
          end
        end

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
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
    |> execute_fun().()
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

  defp execute_fun do
    Application.get_env(:controlkeel, :entry_point_execute_fun, &CLI.execute/1)
  end

  defp application_start_fun do
    Application.get_env(
      :controlkeel,
      :entry_point_application_start_fun,
      &ControlKeel.Application.start_link/0
    )
  end
end
