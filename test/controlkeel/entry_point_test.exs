defmodule ControlKeel.EntryPointTest do
  use ExUnit.Case, async: false

  setup do
    previous = System.get_env("__BURRITO")

    on_exit(fn ->
      if previous do
        System.put_env("__BURRITO", previous)
      else
        System.delete_env("__BURRITO")
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
end
