defmodule ControlKeel.Mcp.StdioAuthorizationTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.Mcp.ToolCall
  alias ControlKeel.MCP.Server
  alias ControlKeel.Mcp.StdioAuthorization
  alias ControlKeel.Project.Binding

  setup do
    previous_guardrails = Application.get_env(:controlkeel, :cloud_mcp_guardrails)
    previous_root = System.get_env("CK_PROJECT_ROOT")

    on_exit(fn ->
      restore_env(:cloud_mcp_guardrails, previous_guardrails)
      restore_project_root(previous_root)
    end)

    :ok
  end

  describe "workspace tool policy" do
    test "denies a tool on the workspace denylist" do
      workspace = workspace_fixture()
      session = session_fixture(workspace: workspace)
      root = bound_root(workspace, session)

      {:ok, _policy} =
        Accounts.set_workspace_tool_policy(workspace.id, "denylist", ["ck_git_commit"])

      assert {:error, {:forbidden, message}} =
               StdioAuthorization.authorize_tool_call(root, "ck_git_commit", %{})

      assert message =~ "ck_git_commit"
      assert message =~ "workspace tool denylist"
    end

    test "denies a tool missing from the workspace allowlist" do
      workspace = workspace_fixture()
      session = session_fixture(workspace: workspace)
      root = bound_root(workspace, session)

      {:ok, _policy} =
        Accounts.set_workspace_tool_policy(workspace.id, "allowlist", ["ck_context"])

      assert {:error, {:forbidden, message}} =
               StdioAuthorization.authorize_tool_call(root, "ck_git_commit", %{})

      assert message =~ "workspace tool allowlist"
    end

    test "allows a tool listed in the workspace allowlist" do
      workspace = workspace_fixture()
      session = session_fixture(workspace: workspace)
      root = bound_root(workspace, session)

      {:ok, _policy} =
        Accounts.set_workspace_tool_policy(workspace.id, "allowlist", ["ck_context"])

      assert :ok = StdioAuthorization.authorize_tool_call(root, "ck_context", %{})
    end

    test "inherits the global default when the workspace has no policy row" do
      workspace = workspace_fixture()
      session = session_fixture(workspace: workspace)
      root = bound_root(workspace, session)

      assert :ok = StdioAuthorization.authorize_tool_call(root, "ck_git_commit", %{})
    end
  end

  describe "guardrails" do
    setup do
      Application.put_env(:controlkeel, :cloud_mcp_guardrails, %{
        enabled: true,
        patterns: [:openai_api_key]
      })

      :ok
    end

    test "denies an argument payload matching a secret pattern" do
      workspace = workspace_fixture()
      session = session_fixture(workspace: workspace)
      root = bound_root(workspace, session)

      assert {:error, {:forbidden, message}} =
               StdioAuthorization.authorize_tool_call(root, "ck_validate", %{
                 "content" => "export OPENAI_KEY=sk-abcdefghijklmnopqrstuvwxyz"
               })

      assert message =~ "guardrail"
      assert message =~ "openai_api_key"
    end

    test "scans with no workspace bound — guardrails need no attribution" do
      root = tmp_root()

      assert {:error, {:forbidden, message}} =
               StdioAuthorization.authorize_tool_call(root, "ck_validate", %{
                 "content" => "sk-abcdefghijklmnopqrstuvwxyz"
               })

      assert message =~ "openai_api_key"
    end

    test "allows a payload with no matching pattern" do
      workspace = workspace_fixture()
      session = session_fixture(workspace: workspace)
      root = bound_root(workspace, session)

      assert :ok =
               StdioAuthorization.authorize_tool_call(root, "ck_validate", %{
                 "content" => "def hello, do: :world"
               })
    end
  end

  describe "audit trail" do
    test "records an allowed stdio call with its workspace" do
      workspace = workspace_fixture()
      session = session_fixture(workspace: workspace)
      root = bound_root(workspace, session)

      assert :ok =
               StdioAuthorization.authorize_tool_call(root, "ck_context", %{
                 "session_id" => session.id
               })

      assert [row] = Repo.all(ToolCall)
      assert row.outcome == "allowed"
      assert row.resource == "mcp-stdio"
      assert row.tool_name == "ck_context"
      assert row.workspace_id == workspace.id
      assert row.denial_reason == nil
      assert row.argument_keys == "session_id"
    end

    test "records a denied stdio call with its policy reason" do
      workspace = workspace_fixture()
      session = session_fixture(workspace: workspace)
      root = bound_root(workspace, session)

      {:ok, _policy} =
        Accounts.set_workspace_tool_policy(workspace.id, "denylist", ["ck_rollback"])

      assert {:error, {:forbidden, _message}} =
               StdioAuthorization.authorize_tool_call(root, "ck_rollback", %{})

      assert [row] = Repo.all(ToolCall)
      assert row.outcome == "denied"
      assert row.resource == "mcp-stdio"
      assert row.tool_name == "ck_rollback"
      assert row.workspace_id == workspace.id
      assert row.denial_reason == "policy:tool_in_workspace_denylist"
    end

    test "records a guardrail denial with the matching pattern" do
      Application.put_env(:controlkeel, :cloud_mcp_guardrails, %{
        enabled: true,
        patterns: [:openai_api_key]
      })

      root = tmp_root()

      assert {:error, {:forbidden, _message}} =
               StdioAuthorization.authorize_tool_call(root, "ck_validate", %{
                 "content" => "sk-abcdefghijklmnopqrstuvwxyz"
               })

      assert [row] = Repo.all(ToolCall)
      assert row.outcome == "denied"
      assert row.workspace_id == nil
      assert row.denial_reason == "guardrail:openai_api_key"
    end
  end

  describe "local single-user mode" do
    test "allows a tool call when no workspace is bound to the project root" do
      root = tmp_root()

      assert :ok = StdioAuthorization.authorize_tool_call(root, "ck_git_commit", %{})
    end

    test "still audits the allowed call with a null workspace" do
      root = tmp_root()

      assert :ok = StdioAuthorization.authorize_tool_call(root, "ck_context", %{})

      assert [row] = Repo.all(ToolCall)
      assert row.outcome == "allowed"
      assert row.resource == "mcp-stdio"
      assert row.workspace_id == nil
    end

    test "denies when the binding exists but does not match the project root" do
      root = tmp_root()

      write_raw_binding(root, %{
        "version" => 1,
        "project_root" => Path.join(root, "some-other-checkout"),
        "workspace_id" => 1,
        "session_id" => 1,
        "agent" => "claude",
        "attached_agents" => %{}
      })

      assert {:error, {:forbidden, message}} =
               StdioAuthorization.authorize_tool_call(root, "ck_git_commit", %{})

      assert message =~ "workspace binding"

      assert [row] = Repo.all(ToolCall)
      assert row.outcome == "denied"
      assert row.denial_reason =~ "binding:"
    end
  end

  describe "stdio transport wiring" do
    setup do
      workspace = workspace_fixture()
      session = session_fixture(workspace: workspace)
      root = bound_root(workspace, session)

      System.put_env("CK_PROJECT_ROOT", root)
      pid = start_supervised!({Server, [start_reader: false, output: :no_response]})

      {:ok, workspace: workspace, session: session, server: pid}
    end

    test "returns a JSON-RPC forbidden error instead of :ok for a denied tool", %{
      server: pid,
      workspace: workspace
    } do
      assert {:ok, _policy} =
               Accounts.set_workspace_tool_policy(workspace.id, "denylist", ["ck_git_commit"])

      response = Server.dispatch_request(pid, tools_call("ck_git_commit", %{}, 1))

      assert %{
               "error" => %{
                 "code" => -32001,
                 "message" => message
               }
             } = response

      assert message =~ "workspace tool denylist"
    end

    test "audits the denial that the transport returned", %{server: pid, workspace: workspace} do
      assert {:ok, _policy} =
               Accounts.set_workspace_tool_policy(workspace.id, "denylist", ["ck_git_commit"])

      Server.dispatch_request(pid, tools_call("ck_git_commit", %{}, 2))

      assert [row] = Repo.all(ToolCall)
      assert row.outcome == "denied"
      assert row.resource == "mcp-stdio"
      assert row.workspace_id == workspace.id
      assert row.denial_reason == "policy:tool_in_workspace_denylist"
    end

    test "dispatches the tool and audits the allowed call when policy permits", %{
      server: pid,
      session: session
    } do
      response =
        Server.dispatch_request(
          pid,
          tools_call(
            "ck_validate",
            %{
              "content" => "SELECT * FROM users",
              "path" => "lib/query_builder.js",
              "kind" => "code",
              "session_id" => session.id
            },
            3
          )
        )

      assert %{"result" => %{"structuredContent" => _payload}} = response

      assert [row] = Repo.all(ToolCall)
      assert row.outcome == "allowed"
      assert row.resource == "mcp-stdio"
      assert row.tool_name == "ck_validate"
      assert row.denial_reason == nil
    end
  end

  defp tools_call(name, arguments, id) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => arguments}
    }
  end

  defp bound_root(workspace, session) do
    root = tmp_root()

    {:ok, _binding} =
      Binding.write(
        %{
          "workspace_id" => workspace.id,
          "session_id" => session.id,
          "agent" => "claude",
          "attached_agents" => %{}
        },
        root
      )

    root
  end

  defp write_raw_binding(root, attrs) do
    path = Binding.path(root)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(attrs))
  end

  defp tmp_root do
    root =
      Path.join(System.tmp_dir!(), "ck-stdio-authz-#{System.unique_integer([:positive])}")

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    root
  end

  defp restore_env(key, nil), do: Application.delete_env(:controlkeel, key)
  defp restore_env(key, value), do: Application.put_env(:controlkeel, key, value)

  defp restore_project_root(nil), do: System.delete_env("CK_PROJECT_ROOT")
  defp restore_project_root(value), do: System.put_env("CK_PROJECT_ROOT", value)
end
