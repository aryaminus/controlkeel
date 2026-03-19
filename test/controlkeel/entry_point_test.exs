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
end
