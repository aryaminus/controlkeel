defmodule ControlKeel.ProtocolInterop do
  @moduledoc false

  alias ControlKeel.MCP.Protocol
  alias ControlKeel.Mission
  alias ControlKeel.Platform.ServiceAccount
  alias ControlKeel.ProtocolAccess
  alias ControlKeelWeb.Endpoint

  @hosted_tool_scope_map %{
    "ck_context" => ["mcp:access", "context:read"],
    "ck_experience_index" => ["mcp:access", "context:read"],
    "ck_experience_read" => ["mcp:access", "context:read"],
    "ck_trace_packet" => ["mcp:access", "context:read"],
    "ck_failure_clusters" => ["mcp:access", "context:read"],
    "ck_skill_evolution" => ["mcp:access", "context:read"],
    "ck_fs_ls" => ["mcp:access", "context:read"],
    "ck_fs_read" => ["mcp:access", "context:read"],
    "ck_fs_find" => ["mcp:access", "context:read"],
    "ck_fs_grep" => ["mcp:access", "context:read"],
    "ck_validate" => ["mcp:access", "validate:run"],
    "ck_finding" => ["mcp:access", "finding:write"],
    "ck_review_submit" => ["mcp:access", "review:write"],
    "ck_review_status" => ["mcp:access", "review:read"],
    "ck_review_feedback" => ["mcp:access", "review:respond"],
    "ck_regression_result" => ["mcp:access", "regression:write"],
    "ck_memory_search" => ["mcp:access", "memory:read"],
    "ck_memory_record" => ["mcp:access", "memory:write"],
    "ck_memory_archive" => ["mcp:access", "memory:write"],
    "ck_budget" => ["mcp:access", "budget:write"],
    "ck_route" => ["mcp:access", "route:read"],
    "ck_delegate" => ["mcp:access", "delegate:run"],
    "ck_cost_optimizer" => ["mcp:access", "cost:read"],
    "ck_outcome_tracker" => ["mcp:access", "outcome:read", "outcome:write"],
    "ck_skill_list" => ["mcp:access", "skills:read"],
    "ck_skill_load" => ["mcp:access", "skills:read"]
  }
  @a2a_skill_ids ~w(
    ck_context
    ck_validate
    ck_finding
    ck_review_submit
    ck_review_status
    ck_review_feedback
    ck_budget
    ck_route
    ck_delegate
  )

  def handle_mcp_request(request, auth_context) when is_map(request) do
    Protocol.handle_request(request,
      tool_names: hosted_tool_names(),
      authorize: fn tool_name, arguments ->
        authorize_hosted_tool_call(auth_context, tool_name, arguments, "mcp")
      end
    )
  end

  def hosted_mcp_scopes do
    @hosted_tool_scope_map
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
  end

  def hosted_tool_names do
    Map.keys(@hosted_tool_scope_map)
  end

  def authorize_hosted_tool_call(auth_context, tool_name, arguments, resource_id)
      when is_map(auth_context) and is_binary(tool_name) and is_map(arguments) do
    with :ok <- verify_resource_access(auth_context, resource_id),
         :ok <- verify_tool_scopes(auth_context.scopes, tool_name, resource_id),
         :ok <- verify_workspace_scope(auth_context.service_account, arguments) do
      :ok
    end
  end

  def handle_a2a_request(request, auth_context) when is_map(request) do
    with %{"jsonrpc" => "2.0", "id" => id, "method" => "message/send", "params" => params} <-
           request,
         :ok <- verify_resource_access(auth_context, "a2a"),
         {:ok, tool_name, arguments, message} <- decode_a2a_message(params),
         :ok <- verify_a2a_tool(tool_name),
         :ok <- authorize_a2a_tool_call(auth_context, tool_name, arguments),
         {:ok, result} <- Protocol.dispatch_tool(tool_name, arguments) do
      json_rpc_ok(id, response_message(message, result))
    else
      %{"jsonrpc" => "2.0", "id" => id} ->
        json_rpc_error(id, -32601, "Method not found")

      {:error, {:forbidden, reason}} ->
        json_rpc_error(Map.get(request, "id"), -32001, reason)

      {:error, {:invalid_arguments, reason}} ->
        json_rpc_error(Map.get(request, "id"), -32602, reason)

      {:error, reason} ->
        json_rpc_error(Map.get(request, "id"), -32000, inspect(reason))

      _ ->
        json_rpc_error(Map.get(request, "id"), -32600, "Invalid Request")
    end
  end

  def agent_card do
    base = Endpoint.url()

    %{
      "name" => "ControlKeel",
      "description" =>
        "Hosted governance agent for ControlKeel context, validation, findings, budgets, routing, and delegated execution.",
      "protocolVersion" => "0.3.0",
      "version" => to_string(Application.spec(:controlkeel, :vsn) || "0.1.0"),
      "url" => base <> "/a2a",
      "skills" => Enum.map(@a2a_skill_ids, &a2a_skill/1),
      "capabilities" => %{"pushNotifications" => false},
      "defaultInputModes" => ["text"],
      "defaultOutputModes" => ["text"],
      "additionalInterfaces" => [
        %{"url" => base <> "/a2a", "transport" => "JSONRPC"}
      ]
    }
  end

  defp authorize_a2a_tool_call(auth_context, tool_name, arguments) do
    with :ok <- verify_tool_scopes(auth_context.scopes, tool_name, "a2a"),
         :ok <- verify_workspace_scope(auth_context.service_account, arguments) do
      :ok
    end
  end

  defp verify_resource_access(%{scopes: scopes}, resource_id) do
    access_scope =
      case ProtocolAccess.normalize_resource(resource_id) do
        {:ok, %{access_scope: scope}} -> scope
        _ -> nil
      end

    if access_scope && access_scope in scopes do
      :ok
    else
      {:error, {:forbidden, "Access token is missing #{access_scope}."}}
    end
  end

  defp verify_tool_scopes(scopes, tool_name, resource_id) do
    case required_tool_scopes(tool_name, resource_id) do
      {:ok, required} ->
        if Enum.all?(required, &(&1 in scopes)) do
          :ok
        else
          {:error, {:forbidden, "Access token is missing the required scopes for #{tool_name}."}}
        end

      {:error, :unsupported_tool} ->
        {:error, {:invalid_arguments, "Unsupported hosted tool"}}
    end
  end

  defp verify_workspace_scope(%ServiceAccount{} = service_account, arguments)
       when is_map(arguments) do
    with :ok <- maybe_verify_session_workspace(service_account, Map.get(arguments, "session_id")),
         :ok <- maybe_verify_task_workspace(service_account, Map.get(arguments, "task_id")),
         :ok <- maybe_verify_review_workspace(service_account, Map.get(arguments, "review_id")),
         :ok <- maybe_verify_workspace_argument(service_account, Map.get(arguments, "workspace_id")) do
      :ok
    end
  end

  defp maybe_verify_session_workspace(_service_account, nil), do: :ok

  defp maybe_verify_session_workspace(%ServiceAccount{} = service_account, session_id) do
    with {:ok, parsed_id} <- parse_integer(session_id, "session_id"),
         %{workspace_id: workspace_id} <- Mission.get_session(parsed_id) do
      if workspace_id == service_account.workspace_id do
        :ok
      else
        {:error, {:forbidden, "Session access is outside the service account workspace."}}
      end
    else
      {:error, reason} -> {:error, reason}
      nil -> :ok
    end
  end

  defp maybe_verify_task_workspace(_service_account, nil), do: :ok

  defp maybe_verify_task_workspace(%ServiceAccount{} = service_account, task_id) do
    with {:ok, parsed_id} <- parse_integer(task_id, "task_id"),
         %{session_id: session_id} <- Mission.get_task(parsed_id),
         %{workspace_id: workspace_id} <- Mission.get_session(session_id) do
      if workspace_id == service_account.workspace_id do
        :ok
      else
        {:error, {:forbidden, "Task access is outside the service account workspace."}}
      end
    else
      {:error, reason} -> {:error, reason}
      nil -> :ok
    end
  end

  defp maybe_verify_review_workspace(_service_account, nil), do: :ok

  defp maybe_verify_review_workspace(%ServiceAccount{} = service_account, review_id) do
    with {:ok, parsed_id} <- parse_integer(review_id, "review_id"),
         %{session_id: session_id} <- Mission.get_review(parsed_id),
         %{workspace_id: workspace_id} <- Mission.get_session(session_id) do
      if workspace_id == service_account.workspace_id do
        :ok
      else
        {:error, {:forbidden, "Review access is outside the service account workspace."}}
      end
    else
      {:error, reason} -> {:error, reason}
      nil -> :ok
    end
  end

  defp maybe_verify_workspace_argument(_service_account, nil), do: :ok

  defp maybe_verify_workspace_argument(%ServiceAccount{} = service_account, workspace_id) do
    with {:ok, parsed_id} <- parse_integer(workspace_id, "workspace_id") do
      if parsed_id == service_account.workspace_id do
        :ok
      else
        {:error, {:forbidden, "Workspace access is outside the service account workspace."}}
      end
    end
  end

  defp required_tool_scopes(tool_name, "a2a") do
    case Map.fetch(@hosted_tool_scope_map, tool_name) do
      {:ok, scopes} ->
        {:ok, scopes |> Enum.reject(&(&1 == "mcp:access")) |> Kernel.++(["a2a:access"])}

      :error ->
        {:error, :unsupported_tool}
    end
  end

  defp required_tool_scopes(tool_name, _resource_id) do
    case Map.fetch(@hosted_tool_scope_map, tool_name) do
      {:ok, scopes} -> {:ok, scopes}
      :error -> {:error, :unsupported_tool}
    end
  end

  defp parse_integer(value, _field) when is_integer(value), do: {:ok, value}

  defp parse_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{field}` must be an integer if provided"}}
    end
  end

  defp parse_integer(_value, field),
    do: {:error, {:invalid_arguments, "`#{field}` must be an integer if provided"}}

  defp verify_a2a_tool(tool_name) when tool_name in @a2a_skill_ids, do: :ok
  defp verify_a2a_tool(_tool_name), do: {:error, {:invalid_arguments, "Unsupported A2A tool"}}

  defp decode_a2a_message(%{"message" => %{"parts" => [part | _]} = message}) do
    with %{"kind" => "text", "text" => payload} <- part,
         {:ok, %{"tool" => tool_name, "arguments" => arguments}} <- Jason.decode(payload),
         true <- is_binary(tool_name) and is_map(arguments) do
      {:ok, tool_name, arguments, message}
    else
      _ ->
        {:error,
         {:invalid_arguments,
          "A2A message payload must be JSON text containing tool and arguments."}}
    end
  end

  defp decode_a2a_message(_params) do
    {:error, {:invalid_arguments, "message/send requires a message payload."}}
  end

  defp response_message(message, result) do
    %{
      "kind" => "message",
      "messageId" => message_id(),
      "role" => "agent",
      "parts" => [%{"kind" => "text", "text" => Jason.encode!(result)}],
      "contextId" => Map.get(message, "contextId")
    }
  end

  defp a2a_skill("ck_context") do
    %{
      "id" => "ck_context",
      "name" => "Mission context",
      "description" => "Read session context, findings, budget, and boundary summary.",
      "tags" => ["context", "governance"]
    }
  end

  defp a2a_skill("ck_validate") do
    %{
      "id" => "ck_validate",
      "name" => "Validation",
      "description" => "Run governed validation before risky code or config changes.",
      "tags" => ["validation", "safety"]
    }
  end

  defp a2a_skill("ck_finding") do
    %{
      "id" => "ck_finding",
      "name" => "Finding persistence",
      "description" => "Persist governed findings and obtain ruling state.",
      "tags" => ["findings", "governance"]
    }
  end

  defp a2a_skill("ck_review_submit") do
    %{
      "id" => "ck_review_submit",
      "name" => "Review submission",
      "description" => "Submit a plan, diff, or completion packet for governed browser review.",
      "tags" => ["review", "planning"]
    }
  end

  defp a2a_skill("ck_review_status") do
    %{
      "id" => "ck_review_status",
      "name" => "Review status",
      "description" => "Check review status, notes, and browser link for the current task.",
      "tags" => ["review", "status"]
    }
  end

  defp a2a_skill("ck_review_feedback") do
    %{
      "id" => "ck_review_feedback",
      "name" => "Review feedback",
      "description" => "Approve or deny a submitted review and return actionable feedback.",
      "tags" => ["review", "approval"]
    }
  end

  defp a2a_skill("ck_budget") do
    %{
      "id" => "ck_budget",
      "name" => "Budget controls",
      "description" => "Estimate or commit governed budget usage.",
      "tags" => ["budget", "cost"]
    }
  end

  defp a2a_skill("ck_route") do
    %{
      "id" => "ck_route",
      "name" => "Agent routing",
      "description" => "Recommend the best AI agent for the current task and risk tier.",
      "tags" => ["routing", "orchestration"]
    }
  end

  defp a2a_skill("ck_delegate") do
    %{
      "id" => "ck_delegate",
      "name" => "Delegated execution",
      "description" => "Ask ControlKeel to run or hand off a task to another governed agent.",
      "tags" => ["delegation", "execution"]
    }
  end

  defp json_rpc_ok(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  defp json_rpc_error(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end

  defp message_id do
    Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  end
end
