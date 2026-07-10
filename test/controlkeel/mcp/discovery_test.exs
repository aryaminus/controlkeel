defmodule ControlKeel.MCP.DiscoveryTest do
  use ExUnit.Case, async: true

  alias ControlKeel.MCP.Discovery

  test "stdio discovery returns actionable unsupported error, not generic transport failure" do
    assert {:error, {:stdio_discovery_unsupported, msg}} =
             Discovery.discover("stdio:///tmp/example", transport: :stdio)

    assert is_binary(msg)
    assert String.contains?(msg, "configured MCP clients")
  end

  test "auto-detected stdio path gets the same actionable error" do
    assert {:error, {:stdio_discovery_unsupported, _msg}} =
             Discovery.discover("/some/local/path")
  end

  test "http discovery blocks loopback targets by default" do
    assert {:error, {:blocked_target, "localhost"}} =
             Discovery.discover("http://localhost:4000/mcp", transport: :http)
  end
end
