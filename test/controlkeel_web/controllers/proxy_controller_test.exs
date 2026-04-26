defmodule ControlKeelWeb.ProxyControllerTest do
  use ControlKeelWeb.ConnCase

  import Phoenix.ConnTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Proxy
  alias ControlKeel.Repo

  setup do
    bypass = Bypass.open()
    previous = Application.get_env(:controlkeel, Proxy, [])

    Application.put_env(
      :controlkeel,
      Proxy,
      Keyword.merge(previous,
        openai_upstream: "http://127.0.0.1:#{bypass.port}",
        anthropic_upstream: "http://127.0.0.1:#{bypass.port}",
        timeout_ms: 1_000
      )
    )

    on_exit(fn -> Application.put_env(:controlkeel, Proxy, previous) end)

    {:ok, bypass: bypass}
  end

  test "passes through safe openai responses requests and commits usage", %{
    conn: conn,
    bypass: bypass
  } do
    session = session_fixture(%{budget_cents: 5_000, daily_budget_cents: 5_000, spent_cents: 0})

    Bypass.expect_once(bypass, "POST", "/v1/responses", fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-key"]

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.put_resp_header("x-ratelimit-remaining-tokens", "149984")
      |> Plug.Conn.put_resp_header("x-ratelimit-reset-tokens", "6m0s")
      |> Plug.Conn.put_resp_header("retry-after", "2")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{
          "output_text" => "all good",
          "usage" => %{"input_tokens" => 8, "output_tokens" => 4}
        })
      )
    end)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-key")
      |> post(
        "/proxy/openai/#{session.proxy_token}/v1/responses",
        Jason.encode!(%{"model" => "gpt-5.4-mini", "input" => "hello"})
      )

    assert json_response(conn, 200)["output_text"] == "all good"
    assert Repo.aggregate(Invocation, :count, :id) == 1

    invocation = Repo.one!(Invocation)
    assert invocation.metadata["rate_limit"]["x-ratelimit-remaining-tokens"] == "149984"
    assert invocation.metadata["rate_limit"]["x-ratelimit-reset-tokens"] == "6m0s"
    assert invocation.metadata["rate_limit"]["retry-after"] == "2"

    assert Mission.get_session!(session.id).spent_cents > 0
  end

  test "blocks fast path violations with an openai-shaped error and never calls upstream", %{
    conn: conn
  } do
    session = session_fixture()

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        "/proxy/openai/#{session.proxy_token}/v1/responses",
        Jason.encode!(%{
          "model" => "gpt-5.4-mini",
          "input" => "SELECT * FROM users WHERE email = '\" + params.email + \"' OR 1=1 --"
        })
      )

    assert %{
             "error" => %{
               "type" => "invalid_request_error",
               "code" => "controlkeel_policy_violation",
               "message" => message
             }
           } = json_response(conn, 400)

    assert message =~ "Blocked"
    assert Repo.aggregate(Invocation, :count, :id) == 0
  end

  test "blocks semgrep-only code findings before forwarding", %{conn: conn} do
    session = session_fixture()

    bin =
      write_semgrep_stub("semgrep-proxy", """
      #!/bin/sh
      cat <<'JSON'
      {"results":[{"check_id":"controlkeel.sql-injection","path":"snippet_1.js","start":{"line":1},"end":{"line":1},"extra":{"message":"bad query","severity":"ERROR","lines":"query = format(\\"SELECT * FROM users WHERE name = %s\\", user_input)","metadata":{"controlkeel_category":"security","controlkeel_rule_id":"security.semgrep.sql_injection","controlkeel_decision":"block","controlkeel_severity":"high"}}}]}
      JSON
      """)

    Application.put_env(
      :controlkeel,
      Proxy,
      Keyword.merge(Application.get_env(:controlkeel, Proxy, []), semgrep_bin: bin)
    )

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        "/proxy/openai/#{session.proxy_token}/v1/responses",
        Jason.encode!(%{
          "model" => "gpt-5.4-mini",
          "input" =>
            "```js\nquery = format(\"SELECT * FROM users WHERE name = %s\", user_input)\n```"
        })
      )

    assert json_response(conn, 400)["error"]["code"] == "controlkeel_policy_violation"
  end

  test "passes through openai completions requests", %{conn: conn, bypass: bypass} do
    session = session_fixture(%{budget_cents: 5_000, daily_budget_cents: 5_000, spent_cents: 0})

    Bypass.expect_once(bypass, "POST", "/v1/completions", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{
          "choices" => [%{"text" => "done"}],
          "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 2}
        })
      )
    end)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        "/proxy/openai/#{session.proxy_token}/v1/completions",
        Jason.encode!(%{"model" => "gpt-5.4-mini", "prompt" => "Finish this"})
      )

    assert json_response(conn, 200)["choices"] |> hd() |> Map.fetch!("text") == "done"
  end

  test "passes through openai embeddings requests", %{conn: conn, bypass: bypass} do
    session = session_fixture(%{budget_cents: 5_000, daily_budget_cents: 5_000, spent_cents: 0})

    Bypass.expect_once(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{
          "data" => [%{"embedding" => [0.1, 0.2], "index" => 0}],
          "usage" => %{"prompt_tokens" => 7, "total_tokens" => 7}
        })
      )
    end)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        "/proxy/openai/#{session.proxy_token}/v1/embeddings",
        Jason.encode!(%{"model" => "text-embedding-3-large", "input" => "hello"})
      )

    assert %{"data" => [%{"index" => 0}]} = json_response(conn, 200)
  end

  test "passes through openai models requests without a JSON body", %{conn: conn, bypass: bypass} do
    session = session_fixture(%{budget_cents: 5_000, daily_budget_cents: 5_000, spent_cents: 0})

    Bypass.expect_once(bypass, "GET", "/v1/models", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{"data" => [%{"id" => "gpt-5.4-mini"}, %{"id" => "gpt-5.4"}]})
      )
    end)

    conn = get(conn, "/proxy/openai/#{session.proxy_token}/v1/models")

    assert Enum.map(json_response(conn, 200)["data"], & &1["id"]) == ["gpt-5.4-mini", "gpt-5.4"]
  end

  test "streams SSE through and terminates with a provider-shaped error on blocked deltas", %{
    conn: conn,
    bypass: bypass
  } do
    session = session_fixture(%{budget_cents: 5_000, daily_budget_cents: 5_000, spent_cents: 0})

    Bypass.expect_once(bypass, "POST", "/v1/responses", fn conn ->
      conn =
        Plug.Conn.put_resp_content_type(conn, "text/event-stream") |> Plug.Conn.send_chunked(200)

      {:ok, conn} =
        Plug.Conn.chunk(
          conn,
          "data: {\"type\":\"response.output_text.delta\",\"text\":\"safe text\"}\n\n"
        )

      {:ok, conn} =
        Plug.Conn.chunk(
          conn,
          "data: {\"type\":\"response.output_text.delta\",\"text\":\"AKIA1234567890ABCDEF\"}\n\n"
        )

      conn
    end)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        "/proxy/openai/#{session.proxy_token}/v1/responses",
        Jason.encode!(%{"model" => "gpt-5.4-mini", "input" => "hello", "stream" => true})
      )

    assert conn.status == 200
    assert conn.resp_body =~ "safe text"
    assert conn.resp_body =~ "controlkeel_policy_violation"
    refute conn.resp_body =~ "AKIA1234567890ABCDEF"
    assert Repo.aggregate(Invocation, :count, :id) == 1
  end

  defp write_semgrep_stub(name, contents) do
    path = Path.join(System.tmp_dir!(), "#{name}-#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
