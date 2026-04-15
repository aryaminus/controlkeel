defmodule ControlKeel.MCP.ProtocolInitializeTest do
  use ExUnit.Case, async: true

  alias ControlKeel.MCP.Protocol

  test "initialize echoes a supported client protocol version" do
    assert %{"result" => %{"protocolVersion" => "2024-11-05"}} =
             Protocol.handle_request(%{
               "jsonrpc" => "2.0",
               "id" => 1,
               "method" => "initialize",
               "params" => %{
                 "protocolVersion" => "2024-11-05",
                 "capabilities" => %{},
                 "clientInfo" => %{"name" => "t", "version" => "1"}
               }
             })
  end

  test "initialize falls back for unknown protocol versions" do
    assert %{"result" => %{"protocolVersion" => "2024-11-05"}} =
             Protocol.handle_request(%{
               "jsonrpc" => "2.0",
               "id" => 2,
               "method" => "initialize",
               "params" => %{"protocolVersion" => "2099-01-01"}
             })
  end
end
