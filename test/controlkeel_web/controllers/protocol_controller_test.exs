defmodule ControlKeelWeb.ProtocolControllerTest do
  use ControlKeelWeb.ConnCase

  import ControlKeel.MissionFixtures
  import ControlKeel.PlatformFixtures

  alias ControlKeel.ProtocolAccess

  describe "OAuth token endpoint" do
    test "issues a client-credentials access token for hosted MCP", %{conn: conn} do
      workspace = workspace_fixture()

      %{service_account: account, token: secret} =
        service_account_fixture(%{
          workspace_id: workspace.id,
          scopes: "mcp:access context:read validate:run"
        })

      conn =
        post(conn, "/oauth/token", %{
          grant_type: "client_credentials",
          client_id: ProtocolAccess.oauth_client_id(account),
          client_secret: secret,
          resource: "mcp",
          scope: "mcp:access context:read validate:run"
        })

      assert %{
               "access_token" => access_token,
               "token_type" => "Bearer",
               "resource" => resource,
               "scope" => "mcp:access context:read validate:run"
             } = json_response(conn, 200)

      assert is_binary(access_token)
      assert resource =~ "/mcp"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "rejects scopes outside the service account grant", %{conn: conn} do
      workspace = workspace_fixture()

      %{service_account: account, token: secret} =
        service_account_fixture(%{
          workspace_id: workspace.id,
          scopes: "mcp:access"
        })

      conn =
        post(conn, "/oauth/token", %{
          grant_type: "client_credentials",
          client_id: ProtocolAccess.oauth_client_id(account),
          client_secret: secret,
          resource: "mcp",
          scope: "mcp:access context:read"
        })

      assert %{"error" => "invalid_scope"} = json_response(conn, 400)
    end
  end

  describe "hosted MCP" do
    test "serves protected-resource metadata and auth-server metadata", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-protected-resource/mcp")
      metadata = json_response(conn, 200)
      assert metadata["resource"] =~ "/mcp"
      assert is_list(metadata["authorization_servers"])

      conn = build_conn() |> get("/.well-known/oauth-authorization-server")
      auth_metadata = json_response(conn, 200)
      assert auth_metadata["token_endpoint"] =~ "/oauth/token"
      assert "client_credentials" in auth_metadata["grant_types_supported"]
    end

    test "rejects unauthenticated hosted MCP requests", %{conn: conn} do
      conn =
        post(conn, "/mcp", %{
          jsonrpc: "2.0",
          id: 1,
          method: "initialize"
        })

      assert %{"error" => "unauthorized"} = json_response(conn, 401)

      [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ "resource_metadata="
      assert challenge =~ "/.well-known/oauth-protected-resource/mcp"
    end

    test "returns 405 for GET and DELETE on /mcp", %{conn: conn} do
      conn = get(conn, "/mcp")
      assert %{"error" => "method_not_allowed"} = json_response(conn, 405)

      conn = build_conn() |> delete("/mcp")
      assert %{"error" => "method_not_allowed"} = json_response(conn, 405)
    end

    test "allows initialize and tools/list with a valid MCP access token", %{conn: conn} do
      token = hosted_token_for("mcp:access")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/mcp", %{
          jsonrpc: "2.0",
          id: 1,
          method: "initialize"
        })

      assert %{"result" => %{"serverInfo" => %{"name" => "controlkeel"}}} =
               json_response(conn, 200)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/mcp", %{
          jsonrpc: "2.0",
          id: 2,
          method: "tools/list"
        })

      assert %{"result" => %{"tools" => tools}} = json_response(conn, 200)
      assert Enum.any?(tools, &(&1["name"] == "ck_validate"))
      assert Enum.any?(tools, &(&1["name"] == "ck_delegate"))
      assert Enum.any?(tools, &(&1["name"] == "ck_regression_result"))
      refute Enum.any?(tools, &(&1["name"] == "ck_deployment_advisor"))
    end

    test "returns 403 when the token lacks the tool scope", %{conn: conn} do
      session = session_fixture()
      token = hosted_token_for("mcp:access")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/mcp", %{
          jsonrpc: "2.0",
          id: 3,
          method: "tools/call",
          params: %{
            name: "ck_context",
            arguments: %{session_id: session.id}
          }
        })

      assert conn.status == 403
      assert %{"error" => %{"code" => -32001}} = json_response(conn, 403)
    end

    test "returns 403 when the session is outside the service-account workspace", %{conn: conn} do
      other_session = session_fixture()

      workspace = workspace_fixture()

      %{service_account: account, token: secret} =
        service_account_fixture(%{
          workspace_id: workspace.id,
          scopes: "mcp:access context:read"
        })

      token =
        request_access_token(
          ProtocolAccess.oauth_client_id(account),
          secret,
          "mcp",
          "mcp:access context:read"
        )

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/mcp", %{
          jsonrpc: "2.0",
          id: 4,
          method: "tools/call",
          params: %{
            name: "ck_context",
            arguments: %{session_id: other_session.id}
          }
        })

      assert conn.status == 403
      assert %{"error" => %{"code" => -32001}} = json_response(conn, 403)
    end

    test "calls a hosted MCP tool with a valid scoped token", %{conn: conn} do
      token = hosted_token_for("mcp:access validate:run")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/mcp", %{
          jsonrpc: "2.0",
          id: 5,
          method: "tools/call",
          params: %{
            name: "ck_validate",
            arguments: %{content: "def hello, do: :world", kind: "code"}
          }
        })

      assert %{
               "result" => %{
                 "structuredContent" => %{"decision" => "allow"}
               }
             } = json_response(conn, 200)
    end

    test "requires delegate:run for ck_delegate", %{conn: conn} do
      task = task_fixture()
      token = hosted_token_for("mcp:access")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/mcp", %{
          jsonrpc: "2.0",
          id: 8,
          method: "tools/call",
          params: %{
            name: "ck_delegate",
            arguments: %{task_id: task.id, mode: "handoff"}
          }
        })

      assert conn.status == 403
      assert %{"error" => %{"code" => -32001}} = json_response(conn, 403)
    end

    test "blocks reproduction-style hosted validation outside verified research", %{conn: conn} do
      workspace = workspace_fixture()

      %{service_account: account, token: secret} =
        service_account_fixture(%{
          workspace_id: workspace.id,
          scopes: "mcp:access validate:run",
          metadata: %{"cyber_access_mode" => "defensive_security"}
        })

      token =
        request_access_token(
          ProtocolAccess.oauth_client_id(account),
          secret,
          "mcp",
          "mcp:access validate:run"
        )

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/mcp", %{
          jsonrpc: "2.0",
          id: 9,
          method: "tools/call",
          params: %{
            name: "ck_validate",
            arguments: %{
              content: "Reproduce the exploit chain against the live target.",
              kind: "text",
              domain_pack: "security",
              security_workflow_phase: "reproduction",
              artifact_type: "repro_steps",
              target_scope: "owned_repo"
            }
          }
        })

      assert conn.status == 403
      assert %{"error" => %{"code" => -32001}} = json_response(conn, 403)
    end
  end

  describe "A2A" do
    test "serves the same agent card from both well-known paths", %{conn: conn} do
      conn = get(conn, "/.well-known/agent-card.json")
      agent_card = json_response(conn, 200)

      conn = build_conn() |> get("/.well-known/agent.json")
      legacy_card = json_response(conn, 200)

      assert agent_card == legacy_card
      assert agent_card["url"] =~ "/a2a"
      assert Enum.any?(agent_card["skills"], &(&1["id"] == "ck_validate"))
      assert Enum.any?(agent_card["skills"], &(&1["id"] == "ck_delegate"))
    end

    test "dispatches message/send to a supported CK capability", %{conn: conn} do
      token = hosted_token_for("a2a:access validate:run", resource: "a2a")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/a2a", %{
          jsonrpc: "2.0",
          id: 6,
          method: "message/send",
          params: %{
            message: %{
              messageId: "msg-1",
              kind: "message",
              role: "user",
              contextId: "ctx-1",
              parts: [
                %{
                  kind: "text",
                  text:
                    Jason.encode!(%{
                      tool: "ck_validate",
                      arguments: %{content: "def hello, do: :world", kind: "code"}
                    })
                }
              ]
            }
          }
        })

      assert %{"result" => %{"kind" => "message", "parts" => [part | _]}} =
               json_response(conn, 200)

      assert %{"decision" => "allow"} = Jason.decode!(part["text"])
    end

    test "returns method not found for unsupported A2A methods", %{conn: conn} do
      token = hosted_token_for("a2a:access", resource: "a2a")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/a2a", %{
          jsonrpc: "2.0",
          id: 7,
          method: "tasks/send"
        })

      assert %{"error" => %{"code" => -32601}} = json_response(conn, 200)
    end
  end

  defp hosted_token_for(scopes, opts \\ []) do
    workspace = workspace_fixture()
    resource = Keyword.get(opts, :resource, "mcp")

    %{service_account: account, token: secret} =
      service_account_fixture(%{
        workspace_id: workspace.id,
        scopes: scopes
      })

    request_access_token(ProtocolAccess.oauth_client_id(account), secret, resource, scopes)
  end

  defp request_access_token(client_id, client_secret, resource, scopes) do
    conn =
      build_conn()
      |> post("/oauth/token", %{
        grant_type: "client_credentials",
        client_id: client_id,
        client_secret: client_secret,
        resource: resource,
        scope: scopes
      })

    json_response(conn, 200)["access_token"]
  end
end
