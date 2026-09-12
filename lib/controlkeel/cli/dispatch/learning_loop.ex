defmodule ControlKeel.CLI.Dispatch.LearningLoop do
  @moduledoc false

  alias ControlKeel.CLI.Output
  alias ControlKeel.Learning.OutcomeTracker
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(
        %{command: :outcome_record, args: [session_id, outcome], options: options},
        _project_root
      ) do
    with {:ok, format} <- effective_cli_format(options),
         {sid, ""} <- Integer.parse(session_id),
         {:ok, outcome_atom} <-
           parse_atom_option(outcome, OutcomeTracker.valid_outcomes(), "outcome") do
      agent_id = "cli-session-#{sid}"

      case OutcomeTracker.record(sid, outcome_atom, agent_id: agent_id) do
        {:ok, result} ->
          payload = %{
            "session_id" => sid,
            "outcome" => outcome,
            "reward" => result.reward
          }

          Output.render_format(format, payload, fn _ ->
            ["Recorded #{outcome} for session ##{session_id} (reward: #{result.reward})"]
          end)

        {:error, {:unknown_outcome, o}} ->
          {:error,
           "Unknown outcome: #{o}. Valid: #{Enum.join(OutcomeTracker.valid_outcomes(), ", ")}"}

        {:error, reason} ->
          {:error, "Failed: " <> inspect(reason)}
      end
    else
      :error ->
        {:error, "`session_id` must be an integer"}

      {:error, _reason} ->
        {:error,
         "Unknown outcome: #{outcome}. Valid: #{Enum.join(OutcomeTracker.valid_outcomes(), ", ")}"}
    end
  end

  # Back-compat: dispatch without options (map without :options key).
  def run_command(%{command: :outcome_record} = parsed, root) do
    run_command(Map.put(parsed, :options, []), root)
  end

  def run_command(%{command: :outcome_score, args: [agent_id], options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, score} <- OutcomeTracker.get_agent_score(agent_id) do
      payload = %{
        "agent_id" => score.agent_id,
        "score" => score.score,
        "outcome_count" => score.outcome_count,
        "total_reward" => score.total_reward,
        "window_days" => score.window_days
      }

      Output.render_format(format, payload, fn _ ->
        [
          "Agent: #{score.agent_id}",
          "Score: #{score.score} (#{score.outcome_count} outcomes, total reward: #{score.total_reward})",
          "Window: #{score.window_days} days"
        ]
      end)
    end
  end

  def run_command(%{command: :outcome_score} = parsed, root) do
    run_command(Map.put(parsed, :options, []), root)
  end

  def run_command(%{command: :outcome_leaderboard, options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, scores} <- OutcomeTracker.get_leaderboard() do
      payload = %{
        "scores" =>
          Enum.map(scores, fn s ->
            %{
              "agent_id" => s.agent_id || "unknown",
              "score" => s.score,
              "outcome_count" => s.outcome_count
            }
          end)
      }

      Output.render_format(format, payload, fn _ ->
        if scores == [] do
          ["No outcomes recorded yet."]
        else
          lines =
            Enum.map(scores, fn s ->
              id = s.agent_id || "unknown"

              id <>
                ": " <>
                to_string(s.score) <> " (" <> to_string(s.outcome_count) <> " outcomes)"
            end)

          ["Agent Leaderboard:", "" | lines]
        end
      end)
    end
  end

  def run_command(%{command: :outcome_leaderboard} = parsed, root) do
    run_command(Map.put(parsed, :options, []), root)
  end
end
