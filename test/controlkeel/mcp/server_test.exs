defmodule ControlKeel.MCP.ServerTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Server

  import ControlKeel.MissionFixtures

  test "server processes framed ck_validate requests over stdio" do
    session = session_fixture()

    request =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/call",
        "params" => %{
          "name" => "ck_validate",
          "arguments" => %{
            "content" =>
              ~s(query = "SELECT * FROM users WHERE email = '" <> params["email"] <> "' OR 1=1 --"),
            "path" => "lib/query_builder.js",
            "kind" => "code",
            "session_id" => session.id
          }
        }
      })

    {:ok, input} = StringIO.open(Server.encode_frame(request))
    {:ok, output} = StringIO.open("")

    {:ok, pid} = Server.start_link(input: input, output: output)
    ref = Process.monitor(pid)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000

    {_input, rendered} = StringIO.contents(output)
    assert rendered =~ "Content-Length:"

    response = decode_framed_json(rendered)

    assert get_in(response, ["result", "structuredContent", "decision"]) == "block"

    assert Enum.any?(
             get_in(response, ["result", "structuredContent", "findings"]),
             &(&1["rule_id"] == "security.sql_injection")
           )
  end

  defp decode_framed_json(frame) do
    [headers, payload] = String.split(frame, "\r\n\r\n", parts: 2)
    assert headers =~ "Content-Length:"
    Jason.decode!(payload)
  end
end
