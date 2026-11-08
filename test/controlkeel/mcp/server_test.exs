defmodule ControlKeel.MCP.ServerTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Server

  import ControlKeel.MissionFixtures

  @launcher Path.expand("../../../bin/controlkeel-mcp", __DIR__)

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
    assert String.ends_with?(rendered, "\n")
    refute rendered =~ "Content-Length:"

    response = decode_stdio_jsonl(rendered)

    assert get_in(response, ["result", "structuredContent", "decision"]) == "block"

    assert Enum.any?(
             get_in(response, ["result", "structuredContent", "findings"]),
             &(&1["rule_id"] == "security.sql_injection")
           )
  end

  @tag :capture_log
  test "MCP launcher emits only one JSONL response on real stdout" do
    request =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 17,
        "method" => "initialize",
        "params" => %{"protocolVersion" => "2024-11-05"}
      })

    tmp_db =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-mcp-server-#{System.unique_integer([:positive])}.db"
      )

    on_exit(fn ->
      File.rm(tmp_db)
      File.rm(tmp_db <> "-wal")
      File.rm(tmp_db <> "-shm")
    end)

    shell =
      ~S(printf '%s\n' "$MCP_REQUEST" | "$MCP_LAUNCHER" --project-root "$CK_PROJECT_ROOT")

    assert {stdout, 0} =
             System.cmd("/bin/sh", ["-c", shell],
               cd: File.cwd!(),
               env: [
                 {"MCP_REQUEST", request},
                 {"MCP_LAUNCHER", @launcher},
                 {"CK_PROJECT_ROOT", File.cwd!()},
                 {"MIX_ENV", "test"},
                 {"DATABASE_PATH", tmp_db},
                 {"CK_TEST_DB", tmp_db},
                 {"CK_TEST_SUBPROCESS", "1"}
               ]
             )

    assert [line] = String.split(stdout, "\n", trim: true)
    refute stdout =~ "Content-Length:"

    assert %{
             "jsonrpc" => "2.0",
             "id" => 17,
             "result" => %{
               "protocolVersion" => "2024-11-05",
               "serverInfo" => %{"name" => "controlkeel"}
             }
           } = Jason.decode!(line)
  end

  defp decode_stdio_jsonl(output) do
    output
    |> String.trim_trailing()
    |> String.split("\n", trim: true)
    |> List.last()
    |> Jason.decode!()
  end
end
