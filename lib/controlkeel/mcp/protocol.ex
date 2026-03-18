defmodule ControlKeel.MCP.Protocol do
  @moduledoc false

  alias ControlKeel.MCP.Tools.{CkBudget, CkContext, CkFinding, CkValidate}

  @server_info %{"name" => "controlkeel", "version" => "0.1.0"}

  def handle_json(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, request} -> handle_request(request)
      {:error, error} -> error_response(nil, -32700, "Parse error: #{Exception.message(error)}")
    end
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => "initialize", "id" => id}) do
    ok_response(id, %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{"tools" => %{"listChanged" => false}},
      "serverInfo" => @server_info
    })
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}),
    do: :no_response

  def handle_request(%{"jsonrpc" => "2.0", "method" => "tools/list", "id" => id}) do
    ok_response(id, %{"tools" => tool_schemas()})
  end

  def handle_request(%{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => id,
        "params" => params
      }) do
    case params do
      %{"name" => "ck_validate", "arguments" => arguments} ->
        tool_response(id, CkValidate.call(arguments))

      %{"name" => "ck_context", "arguments" => arguments} ->
        tool_response(id, CkContext.call(arguments))

      %{"name" => "ck_finding", "arguments" => arguments} ->
        tool_response(id, CkFinding.call(arguments))

      %{"name" => "ck_budget", "arguments" => arguments} ->
        tool_response(id, CkBudget.call(arguments))

      %{"name" => unknown} ->
        error_response(id, -32601, "Unknown tool: #{unknown}")

      _other ->
        error_response(id, -32602, "tools/call requires a tool name and arguments")
    end
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => _method, "id" => id}) do
    error_response(id, -32601, "Method not found")
  end

  def handle_request(_request) do
    error_response(nil, -32600, "Invalid Request")
  end

  def ck_validate_tool do
    %{
      "name" => "ck_validate",
      "description" => "Validate proposed code, config, shell, or text content before execution.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "content" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "kind" => %{"type" => "string", "enum" => ["code", "config", "shell", "text"]},
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_context_tool do
    %{
      "name" => "ck_context",
      "description" =>
        "Fetch the current mission, risk, finding, and budget context for a session.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_finding_tool do
    %{
      "name" => "ck_finding",
      "description" => "Persist a governed finding and return the ruling state.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "category", "severity", "rule_id", "plain_message"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "category" => %{"type" => "string"},
          "severity" => %{"type" => "string"},
          "rule_id" => %{"type" => "string"},
          "plain_message" => %{"type" => "string"},
          "title" => %{"type" => "string"},
          "decision" => %{
            "type" => "string",
            "enum" => ["allow", "warn", "block", "escalate_to_human"]
          },
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_budget_tool do
    %{
      "name" => "ck_budget",
      "description" =>
        "Estimate or record the cost of an agent operation against session and daily budgets.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "mode" => %{"type" => "string", "enum" => ["estimate", "commit"]},
          "estimated_cost_cents" => %{"type" => ["integer", "string"]},
          "provider" => %{"type" => "string"},
          "model" => %{"type" => "string"},
          "input_tokens" => %{"type" => ["integer", "string"]},
          "cached_input_tokens" => %{"type" => ["integer", "string"]},
          "output_tokens" => %{"type" => ["integer", "string"]},
          "source" => %{"type" => "string"},
          "tool" => %{"type" => "string"},
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  defp tool_schemas do
    [ck_validate_tool(), ck_context_tool(), ck_finding_tool(), ck_budget_tool()]
  end

  defp tool_response(id, {:ok, result}) do
    ok_response(id, %{
      "content" => [%{"type" => "text", "text" => Jason.encode!(result)}],
      "structuredContent" => result
    })
  end

  defp tool_response(id, {:error, {:invalid_arguments, reason}}),
    do: error_response(id, -32602, reason)

  defp tool_response(id, {:error, reason}), do: error_response(id, -32000, inspect(reason))

  defp ok_response(id, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  defp error_response(id, code, message) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    }
  end
end
