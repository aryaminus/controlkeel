defmodule ControlKeel.Performance.CriticalPathsTest do
  use ExUnit.Case, async: false

  alias ControlKeel.MCP.Server

  @moduletag :performance
  @tools_list_budget_ms 3_000

  test "MCP tools/list stays within its operator-facing latency budget" do
    {:ok, server} = Server.start_link(start_reader: false)

    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/list",
      "params" => %{}
    }

    {elapsed_us, response} =
      :timer.tc(fn -> GenServer.call(server, {:dispatch, request}, 30_000) end)

    tools = get_in(response, ["result", "tools"])
    elapsed_ms = System.convert_time_unit(elapsed_us, :microsecond, :millisecond)

    assert is_list(tools)
    assert length(tools) >= 50

    assert elapsed_ms <= @tools_list_budget_ms,
           "tools/list took #{elapsed_ms} ms; budget is #{@tools_list_budget_ms} ms"

    GenServer.stop(server)
  end
end
