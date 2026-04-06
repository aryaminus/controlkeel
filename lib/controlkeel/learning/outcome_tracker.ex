defmodule ControlKeel.Learning.OutcomeTracker do
  @moduledoc false

  alias ControlKeel.Memory
  alias ControlKeel.Mission

  @outcomes %{
    deploy_success: %{reward: 1.0, label: "Deploy Succeeded"},
    deploy_failure: %{reward: -1.0, label: "Deploy Failed"},
    test_pass: %{reward: 0.5, label: "Tests Passed"},
    test_fail: %{reward: -0.5, label: "Tests Failed"},
    security_scan_clean: %{reward: 0.3, label: "Security Scan Clean"},
    security_scan_found: %{reward: -0.3, label: "Security Scan Found Issues"},
    user_approval: %{reward: 0.8, label: "User Approved"},
    user_rejection: %{reward: -0.8, label: "User Rejected"},
    budget_on_target: %{reward: 0.2, label: "Budget On Target"},
    budget_exceeded: %{reward: -0.4, label: "Budget Exceeded"}
  }

  def record(session_id, outcome, opts \\ []) do
    case Map.get(@outcomes, outcome) do
      nil ->
        {:error, {:unknown_outcome, outcome}}

      outcome_def ->
        agent_id = Keyword.get(opts, :agent_id)
        task_type = Keyword.get(opts, :task_type)
        workspace_id = Keyword.get(opts, :workspace_id) || workspace_id_for_session(session_id)
        metadata = Keyword.get(opts, :metadata, %{})

        attrs = %{
          workspace_id: workspace_id,
          session_id: session_id,
          record_type: "decision",
          title: "Outcome: #{outcome_def.label}",
          summary: "Agent #{agent_id} recorded outcome #{outcome_def.label}",
          body: outcome_to_text(agent_id, outcome_def.label, session_id, outcome_def.reward),
          tags:
            ["outcome", to_string(outcome), agent_id || "unknown", task_type || "unknown"]
            |> Enum.reject(&is_nil/1),
          source_type: "outcome_tracker",
          source_id: "outcome:#{session_id}:#{outcome}:#{System.unique_integer([:positive])}",
          metadata:
            Map.merge(metadata, %{
              outcome: to_string(outcome),
              reward: outcome_def.reward,
              label: outcome_def.label,
              agent_id: agent_id,
              task_type: task_type,
              session_id: session_id,
              recorded_at: DateTime.utc_now() |> DateTime.to_iso8601()
            })
        }

        case Memory.record(attrs) do
          {:ok, record} ->
            {:ok, %{id: record.id, outcome: outcome, reward: outcome_def.reward}}

          {:error, _} = err ->
            err
        end
    end
  end

  def get_session_outcomes(session_id) do
    case Memory.search("outcome session:#{session_id}",
           session_id: session_id,
           workspace_id: workspace_id_for_session(session_id),
           top_k: 200
         ) do
      %{entries: entries} ->
        outcomes =
          entries
          |> Enum.filter(fn e ->
            tags = Map.get(e, :tags, [])
            "outcome" in tags
          end)
          |> Enum.map(fn e ->
            Map.get(e, :metadata, %{})
            |> Map.put(:id, Map.get(e, :id))
          end)

        {:ok, outcomes}
    end
  end

  def get_agent_score(agent_id, opts \\ []) do
    window = Keyword.get(opts, :window, 30)
    cutoff = DateTime.utc_now() |> DateTime.add(-window * 24 * 60 * 60, :second)

    case Memory.search("outcome agent:#{agent_id}", top_k: 500) do
      %{entries: entries} ->
        outcomes =
          entries
          |> Enum.filter(fn e ->
            meta = Map.get(e, :metadata, %{})

            Map.get(meta, "agent_id") == agent_id and
              within_window?(Map.get(meta, "recorded_at", ""), cutoff)
          end)
          |> Enum.map(fn e -> Map.get(e, :metadata, %{}) end)

        rewards = Enum.map(outcomes, fn m -> Map.get(m, "reward", 0) end)
        count = length(rewards)
        total_reward = Enum.sum(rewards)
        score = if count > 0, do: total_reward / count, else: 0.0

        {:ok,
         %{
           agent_id: agent_id,
           score: Float.round(score * 1.0, 3),
           total_reward: Float.round(total_reward * 1.0, 3),
           outcome_count: count,
           window_days: window,
           breakdown: group_outcomes(outcomes)
         }}
    end
  end

  def get_leaderboard(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    window = Keyword.get(opts, :window, 30)
    workspace_id = Keyword.get(opts, :workspace_id)

    case Memory.search("outcome agent:", top_k: 1000, workspace_id: workspace_id) do
      %{entries: entries} ->
        cutoff = DateTime.utc_now() |> DateTime.add(-window * 24 * 60 * 60, :second)

        agent_scores =
          entries
          |> Enum.map(fn e -> Map.get(e, :metadata, %{}) end)
          |> Enum.filter(fn m ->
            Map.has_key?(m, "agent_id") and
              within_window?(Map.get(m, "recorded_at", ""), cutoff)
          end)
          |> Enum.group_by(fn m -> Map.get(m, "agent_id") end)
          |> Enum.map(fn {agent_id, outcomes} ->
            rewards = Enum.map(outcomes, fn m -> Map.get(m, "reward", 0) end)
            avg = if length(rewards) > 0, do: Enum.sum(rewards) / length(rewards), else: 0.0

            %{
              agent_id: agent_id,
              score: Float.round(avg, 3),
              outcome_count: length(outcomes),
              total_reward: Float.round(Enum.sum(rewards), 3)
            }
          end)
          |> Enum.sort_by(& &1.score, :desc)
          |> Enum.take(limit)

        {:ok, agent_scores}
    end
  end

  def compute_router_weights do
    case get_leaderboard(limit: 50) do
      {:ok, scores} when is_list(scores) and length(scores) > 0 ->
        total_abs =
          scores
          |> Enum.map(fn s -> abs(s.score) + 0.01 end)
          |> Enum.sum()

        weights =
          scores
          |> Enum.map(fn s ->
            normalized = (abs(s.score) + 0.01) / total_abs
            {s.agent_id, Float.round(normalized, 4)}
          end)
          |> Map.new()

        {:ok, weights}

      _ ->
        {:ok, %{}}
    end
  end

  def valid_outcomes do
    Map.keys(@outcomes)
  end

  defp workspace_id_for_session(session_id) do
    case Mission.get_session(session_id) do
      %{workspace_id: workspace_id} -> workspace_id
      _ -> nil
    end
  end

  defp within_window?(iso_datetime, cutoff) do
    case DateTime.from_iso8601(iso_datetime) do
      {:ok, dt, _} -> DateTime.compare(dt, cutoff) in [:gt, :eq]
      _ -> false
    end
  end

  defp outcome_to_text(agent_id, label, session_id, reward) do
    "Agent #{agent_id} outcome #{label} in session #{session_id} with reward #{reward}"
  end

  defp group_outcomes(outcomes) do
    outcomes
    |> Enum.group_by(fn m -> Map.get(m, "outcome", "unknown") end)
    |> Enum.map(fn {outcome, group} ->
      total = group |> Enum.map(fn m -> Map.get(m, "reward", 0) end) |> Enum.sum()

      %{outcome: outcome, count: length(group), total_reward: total}
    end)
  end
end
