defmodule ControlKeel.EntryPointTest do
  use ExUnit.Case, async: false

  alias ControlKeel.CLI

  import ExUnit.CaptureIO

  setup do
    previous = System.get_env("__BURRITO")

    previous_plain_arguments_provider =
      Application.get_env(:controlkeel, :cli_plain_arguments_provider)

    previous_halt_fun = Application.get_env(:controlkeel, :entry_point_halt_fun)
    previous_execute_fun = Application.get_env(:controlkeel, :entry_point_execute_fun)

    previous_application_start_fun =
      Application.get_env(:controlkeel, :entry_point_application_start_fun)

    previous_endpoint_config = Application.get_env(:controlkeel, ControlKeelWeb.Endpoint)

    previous_logger_handler = :logger.get_handler_config(:default)

    on_exit(fn ->
      if previous do
        System.put_env("__BURRITO", previous)
      else
        System.delete_env("__BURRITO")
      end

      if previous_plain_arguments_provider do
        Application.put_env(
          :controlkeel,
          :cli_plain_arguments_provider,
          previous_plain_arguments_provider
        )
      else
        Application.delete_env(:controlkeel, :cli_plain_arguments_provider)
      end

      if previous_halt_fun do
        Application.put_env(:controlkeel, :entry_point_halt_fun, previous_halt_fun)
      else
        Application.delete_env(:controlkeel, :entry_point_halt_fun)
      end

      if previous_execute_fun do
        Application.put_env(:controlkeel, :entry_point_execute_fun, previous_execute_fun)
      else
        Application.delete_env(:controlkeel, :entry_point_execute_fun)
      end

      if previous_application_start_fun do
        Application.put_env(
          :controlkeel,
          :entry_point_application_start_fun,
          previous_application_start_fun
        )
      else
        Application.delete_env(:controlkeel, :entry_point_application_start_fun)
      end

      if previous_endpoint_config do
        Application.put_env(:controlkeel, ControlKeelWeb.Endpoint, previous_endpoint_config)
      else
        Application.delete_env(:controlkeel, ControlKeelWeb.Endpoint)
      end

      case previous_logger_handler do
        {:ok, handler} ->
          restore_default_logger_handler(handler)

        _ ->
          :ok
      end
    end)

    :ok
  end

  test "standalone_runtime? follows the Burrito runtime marker" do
    System.put_env("__BURRITO", "1")
    assert ControlKeel.EntryPoint.standalone_runtime?()

    System.delete_env("__BURRITO")
    refute ControlKeel.EntryPoint.standalone_runtime?()
  end

  test "standalone_argv uses plain arguments in a Burrito runtime" do
    System.put_env("__BURRITO", "1")
    Application.put_env(:controlkeel, :cli_plain_arguments_provider, fn -> [~c"help"] end)

    assert CLI.standalone_argv() == ["help"]
  end

  test "standalone start redirects default logger handler to stderr" do
    parent = self()

    System.put_env("__BURRITO", "1")
    Application.put_env(:controlkeel, :cli_plain_arguments_provider, fn -> [~c"help"] end)

    configure_default_logger_type(:standard_io)

    Application.put_env(:controlkeel, :entry_point_halt_fun, fn exit_code ->
      send(parent, {:halted, exit_code})
      :ok
    end)

    capture_io(fn ->
      assert {:ok, _pid} = ControlKeel.EntryPoint.start(:normal, [])
    end)

    assert_receive {:halted, 0}

    assert {:ok, %{config: config}} = :logger.get_handler_config(:default)
    assert config[:type] == :standard_error
  end

  test "standalone help executes and halts synchronously" do
    parent = self()

    System.put_env("__BURRITO", "1")
    Application.put_env(:controlkeel, :cli_plain_arguments_provider, fn -> [~c"help"] end)

    Application.put_env(:controlkeel, :entry_point_halt_fun, fn exit_code ->
      send(parent, {:halted, exit_code})
      :ok
    end)

    capture_io(fn ->
      assert {:ok, _pid} = ControlKeel.EntryPoint.start(:normal, [])
    end)

    assert_receive {:halted, 0}
  end

  test "non-server standalone commands disable endpoint watchers and reloader" do
    parent = self()

    System.put_env("__BURRITO", "1")

    Application.put_env(:controlkeel, :cli_plain_arguments_provider, fn ->
      [~c"attach", ~c"doctor", ~c"--project-root", ~c"/tmp"]
    end)

    Application.put_env(:controlkeel, ControlKeelWeb.Endpoint,
      watchers: [tailwind: {Tailwind, :install_and_run, [:controlkeel, ~w(--watch)]}],
      code_reloader: true,
      live_reload: [web_console_logger: true, patterns: [~r"foo"]],
      server: true
    )

    Application.put_env(:controlkeel, :entry_point_application_start_fun, fn ->
      send(parent, {:endpoint_config, Application.get_env(:controlkeel, ControlKeelWeb.Endpoint)})
      {:ok, self()}
    end)

    Application.put_env(:controlkeel, :entry_point_execute_fun, fn parsed ->
      send(parent, {:executed, parsed})
      0
    end)

    Application.put_env(:controlkeel, :entry_point_halt_fun, fn exit_code ->
      send(parent, {:halted, exit_code})
      :ok
    end)

    assert {:ok, _pid} = ControlKeel.EntryPoint.start(:normal, [])

    assert_receive {:endpoint_config, endpoint_config}
    assert endpoint_config[:watchers] == []
    assert endpoint_config[:code_reloader] == false
    assert endpoint_config[:server] == false
    assert endpoint_config[:live_reload] == [web_console_logger: false, patterns: []]

    assert_receive {:executed, %{command: :attach_doctor}}
    assert_receive {:halted, 0}
  end

  test "standalone app command executes and halts synchronously after app startup" do
    parent = self()

    System.put_env("__BURRITO", "1")

    Application.put_env(:controlkeel, :cli_plain_arguments_provider, fn ->
      [~c"init", ~c"--no-attach"]
    end)

    Application.put_env(:controlkeel, :entry_point_application_start_fun, fn ->
      send(parent, :application_started)
      {:ok, self()}
    end)

    Application.put_env(:controlkeel, :entry_point_execute_fun, fn parsed ->
      send(parent, {:executed, parsed})
      0
    end)

    Application.put_env(:controlkeel, :entry_point_halt_fun, fn exit_code ->
      send(parent, {:halted, exit_code})
      :ok
    end)

    assert {:ok, _pid} = ControlKeel.EntryPoint.start(:normal, [])
    assert_receive :application_started
    assert_receive {:executed, %{command: :init}}
    assert_receive {:halted, 0}
  end

  defp configure_default_logger_type(type) do
    case :logger.get_handler_config(:default) do
      {:ok, %{module: module} = handler} ->
        replacement = %{handler | config: Map.put(handler.config || %{}, :type, type)}

        with :ok <- :logger.remove_handler(:default),
             {:ok, _handler_id} <- :logger.add_handler(:default, module, replacement) do
          :ok
        else
          _ -> :ok
        end

      _ ->
        :ok
    end
  end

  defp restore_default_logger_handler(handler) do
    with :ok <- :logger.remove_handler(:default),
         {:ok, _handler_id} <- :logger.add_handler(:default, handler.module, handler) do
      :ok
    else
      _ -> :ok
    end
  end
end
