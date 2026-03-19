defmodule ControlKeel.EntryPointTest do
  use ExUnit.Case, async: false

  alias ControlKeel.CLI

  setup do
    previous = System.get_env("__BURRITO")

    previous_plain_arguments_provider =
      Application.get_env(:controlkeel, :cli_plain_arguments_provider)

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
end
