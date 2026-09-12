defmodule ControlKeel.MCP.Tools.CkCopilot do
  @moduledoc false

  alias ControlKeel.Governance.CopilotChannel
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    try do
      do_call(arguments)
    rescue
      e -> {:error, "Copilot operation failed: #{Exception.message(e)}"}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp do_call(arguments) do
    with {:ok, session} <- Arguments.fetch_session(arguments) do
      session_id = session.id
      mode = Map.get(arguments, "mode", "history")

      case mode do
        "subscribe" ->
          CopilotChannel.subscribe(session_id)
          {:ok, %{"status" => "subscribed", "session_id" => session_id}}

        "publish" ->
          event_type = arguments["event_type"]
          payload = arguments["payload"] || %{}

          case event_type do
            nil ->
              {:error, {:invalid_arguments, "`event_type` is required for publish mode"}}

            et
            when et in ~w(human.viewing human.editing human.approving human.commenting agent.status agent.progress) ->
              with :ok <-
                     Arguments.validate_task(
                       Arguments.parse_integer(arguments["task_id"]),
                       session_id
                     ) do
                CopilotChannel.publish(session_id, et, payload,
                  actor: arguments["actor"] || "unknown",
                  task_id: Arguments.parse_integer(arguments["task_id"])
                )

                {:ok, %{"status" => "published", "session_id" => session_id, "event_type" => et}}
              end

            _ ->
              {:error,
               {:invalid_arguments,
                "Invalid event_type. Must be one of: human.viewing, human.editing, human.approving, human.commenting, agent.status, agent.progress"}}
          end

        "presence" ->
          {:ok, CopilotChannel.presence(session_id)}

        "history" ->
          limit = Arguments.parse_integer(arguments["limit"]) || 50
          {:ok, events} = CopilotChannel.history(session_id, limit: limit)
          {:ok, %{"events" => Enum.map(events, &format_event/1), "count" => length(events)}}

        _ ->
          {:error, {:invalid_arguments, "mode must be subscribe, publish, presence, or history"}}
      end
    end
  end

  defp format_event(event) do
    %{
      "id" => event.id,
      "session_id" => event.session_id,
      "event_type" => event.event_type,
      "actor" => event.actor,
      "task_id" => event.task_id,
      "payload" => event.payload,
      "timestamp" => event.timestamp
    }
  end
end
