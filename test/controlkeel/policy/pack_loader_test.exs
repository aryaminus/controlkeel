defmodule ControlKeel.Policy.PackLoaderTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Policy.{PackLoader, Rule}

  setup do
    PackLoader.clear_cache()
    :ok
  end

  test "missing pack fails clearly" do
    assert {:error, {:pack_not_found, "missing-pack"}} = PackLoader.load("missing-pack")
  end

  test "malformed pack fails clearly" do
    path = temp_path("malformed-pack.json")
    File.write!(path, "{not valid json")
    on_exit(fn -> File.rm(path) end)

    assert {:error, {:decode_failed, ^path, _message}} = PackLoader.load_from_path(path)
  end

  test "baseline and cost packs load into normalized runtime rules" do
    assert {:ok, baseline} = PackLoader.load("baseline")
    assert {:ok, cost} = PackLoader.load("cost")

    assert Enum.all?(baseline ++ cost, &match?(%Rule{}, &1))
    assert Enum.any?(baseline, &(&1.id == "security.sql_injection"))
    assert Enum.any?(cost, &(&1.id == "cost.budget_guard"))
  end

  defp temp_path(name) do
    Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{name}")
  end
end
