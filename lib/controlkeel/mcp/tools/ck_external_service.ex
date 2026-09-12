defmodule ControlKeel.MCP.Tools.CkExternalService do
  @moduledoc false

  alias ControlKeel.Governance.ExternalServiceTracker
  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Utils

  def call(arguments) when is_map(arguments) do
    try do
      do_call(arguments)
    rescue
      e -> {:error, "External service operation failed: #{Exception.message(e)}"}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp do_call(arguments) do
    with {:ok, session} <- Arguments.fetch_session(arguments) do
      id = session.id
      mode = Map.get(arguments, "mode", "summary")

      case mode do
        "record" ->
          attrs = %{
            session_id: id,
            task_id: Arguments.parse_integer(arguments["task_id"]),
            service_name: arguments["service_name"],
            interaction_type: arguments["interaction_type"] || "api_call",
            method: arguments["method"],
            endpoint: arguments["endpoint"],
            status_code: Arguments.parse_integer(arguments["status_code"]),
            request_size_bytes: Arguments.parse_integer(arguments["request_size_bytes"]) || 0,
            response_size_bytes: Arguments.parse_integer(arguments["response_size_bytes"]) || 0,
            latency_ms: Arguments.parse_integer(arguments["latency_ms"]),
            tokens_used: Arguments.parse_integer(arguments["tokens_used"]) || 0,
            cost_cents: Arguments.parse_integer(arguments["cost_cents"]) || 0,
            metadata: arguments["metadata"] || %{}
          }

          with :ok <- Arguments.validate_task(attrs.task_id, id) do
            case ExternalServiceTracker.record(attrs) do
              {:ok, interaction} ->
                {:ok, format_interaction(interaction)}

              {:error, changeset} ->
                {:error, {:invalid_arguments, Utils.format_changeset_errors(changeset)}}
            end
          end

        "summary" ->
          {:ok, ExternalServiceTracker.summary(id)}

        "rate_limit_status" ->
          {:ok, ExternalServiceTracker.rate_limit_status(id)}

        "top_services" ->
          limit = Arguments.parse_integer(arguments["limit"]) || 10
          services = ExternalServiceTracker.top_services(id, limit: limit)
          {:ok, %{"services" => services, "count" => length(services)}}

        _ ->
          {:error,
           {:invalid_arguments,
            "mode must be record, summary, rate_limit_status, or top_services"}}
      end
    end
  end

  defp format_interaction(interaction) do
    %{
      "id" => interaction.id,
      "session_id" => interaction.session_id,
      "task_id" => interaction.task_id,
      "service_name" => interaction.service_name,
      "interaction_type" => interaction.interaction_type,
      "method" => interaction.method,
      "endpoint" => interaction.endpoint,
      "status_code" => interaction.status_code,
      "latency_ms" => interaction.latency_ms,
      "cost_cents" => interaction.cost_cents,
      "redacted" => interaction.redacted
    }
  end
end
