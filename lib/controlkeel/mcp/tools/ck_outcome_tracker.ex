defmodule ControlKeel.MCP.Tools.CkOutcomeTracker do
  @moduledoc false

  alias ControlKeel.Learning.OutcomeTracker

  @allowed_modes ~w(record get_session get_leaderboard)

  def call(arguments) when is_map(arguments) do
    with {:ok, normalized} <- normalize(arguments) do
      case normalized["mode"] do
        "record" ->
          opts = [
            agent_id: normalized["agent_id"],
            task_type: normalized["task_type"],
            workspace_id: normalized["workspace_id"],
            metadata: normalized["metadata"] || %{}
          ]

          OutcomeTracker.record(
            normalized["session_id"],
            String.to_atom(normalized["outcome"]),
            opts
          )

        "get_session" ->
          OutcomeTracker.get_session_outcomes(normalized["session_id"])

        "get_leaderboard" ->
          opts = [
            limit: normalized["limit"],
            window: normalized["window"]
          ]

          OutcomeTracker.get_leaderboard(opts)
      end
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments) do
    with {:ok, mode} <- mode(arguments) do
      cond do
        mode == "record" and is_nil(Map.get(arguments, "session_id")) ->
          {:error, {:invalid_arguments, "`session_id` is required for record mode"}}

        mode == "record" and is_nil(Map.get(arguments, "outcome")) ->
          {:error, {:invalid_arguments, "`outcome` is required for record mode"}}

        mode == "get_session" and is_nil(Map.get(arguments, "session_id")) ->
          {:error, {:invalid_arguments, "`session_id` is required for get_session mode"}}

        true ->
          {:ok,
           %{
             "mode" => mode,
             "session_id" => Map.get(arguments, "session_id"),
             "outcome" => Map.get(arguments, "outcome"),
             "agent_id" => Map.get(arguments, "agent_id"),
             "task_type" => Map.get(arguments, "task_type"),
             "workspace_id" => Map.get(arguments, "workspace_id"),
             "metadata" => Map.get(arguments, "metadata", %{}),
             "limit" => Map.get(arguments, "limit", 20),
             "window" => Map.get(arguments, "window", 30)
           }}
      end
    end
  end

  defp mode(arguments) do
    case Map.get(arguments, "mode", "record") do
      value when value in @allowed_modes ->
        {:ok, value}

      _ ->
        {:error,
         {:invalid_arguments, "`mode` must be `record`, `get_session`, or `get_leaderboard`"}}
    end
  end
end
