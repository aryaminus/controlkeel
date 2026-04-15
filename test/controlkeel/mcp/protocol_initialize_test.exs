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

  test "handle_json rejects an empty JSON-RPC batch array" do
    assert %{"error" => %{"code" => -32600}, "id" => nil} = Protocol.handle_json("[]")
  end

  test "handle_json returns no response for an all-notification batch" do
    batch =
      Jason.encode!([
        %{
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized"
        }
      ])

    assert :no_response = Protocol.handle_json(batch)
  end

  test "handle_json batch returns one result per non-notification request" do
    batch =
      Jason.encode!([
        %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{
            "protocolVersion" => "2024-11-05",
            "capabilities" => %{},
            "clientInfo" => %{"name" => "t", "version" => "1"}
          }
        },
        %{"jsonrpc" => "2.0", "method" => "notifications/initialized"},
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}
      ])

    assert [r1, r2] = Protocol.handle_json(batch)
    assert %{"id" => 1, "result" => %{"protocolVersion" => "2024-11-05"}} = r1
    assert %{"id" => 2, "result" => %{"tools" => tools}} = r2
    assert is_list(tools)
  end
end
