defmodule ControlKeel.Learning.OutcomeTrackerTest do
  use ControlKeel.DataCase

  alias ControlKeel.Learning.OutcomeTracker
  import ControlKeel.MissionFixtures

  test "record persists a valid outcome" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    assert {:ok, result} =
             OutcomeTracker.record(session.id, :deploy_success,
               agent_id: "claude",
               task_type: "deployment",
               workspace_id: workspace.workspace_id
             )

    assert result.outcome == :deploy_success
    assert result.reward == 1.0
  end

  test "record infers workspace from the session when omitted" do
    session = session_fixture()

    assert {:ok, result} =
             OutcomeTracker.record(session.id, :deploy_success,
               agent_id: "claude",
               task_type: "deployment"
             )

    assert result.outcome == :deploy_success
  end

  test "record rejects unknown outcome" do
    session = session_fixture()

    assert {:error, {:unknown_outcome, :bogus}} =
             OutcomeTracker.record(session.id, :bogus)
  end

  test "valid_outcomes lists all supported outcomes" do
    outcomes = OutcomeTracker.valid_outcomes()
    assert :deploy_success in outcomes
    assert :deploy_failure in outcomes
    assert :test_pass in outcomes
    assert :budget_exceeded in outcomes
    assert length(outcomes) == 10
  end

  test "rewards have expected sign and range" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    assert {:ok, pos} =
             OutcomeTracker.record(session.id, :deploy_success,
               agent_id: "a",
               workspace_id: workspace.workspace_id
             )

    assert pos.reward > 0

    assert {:ok, neg} =
             OutcomeTracker.record(session.id, :deploy_failure,
               agent_id: "a",
               workspace_id: workspace.workspace_id
             )

    assert neg.reward < 0
  end

  test "get_agent_score returns zero for unknown agent" do
    assert {:ok, score} = OutcomeTracker.get_agent_score("nonexistent_agent_xyz")
    assert score.score == 0.0
    assert score.outcome_count == 0
  end

  test "get_leaderboard returns list" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    OutcomeTracker.record(session.id, :deploy_success,
      agent_id: "lb_good",
      workspace_id: workspace.workspace_id
    )

    OutcomeTracker.record(session.id, :deploy_failure,
      agent_id: "lb_bad",
      workspace_id: workspace.workspace_id
    )

    assert {:ok, leaderboard} =
             OutcomeTracker.get_leaderboard(workspace_id: workspace.workspace_id)

    assert is_list(leaderboard)
  end

  test "get_session_outcomes returns outcomes for a session" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    {:ok, _} =
      OutcomeTracker.record(session.id, :deploy_success,
        agent_id: "so_1",
        workspace_id: workspace.workspace_id
      )

    {:ok, _} =
      OutcomeTracker.record(session.id, :test_pass,
        agent_id: "so_2",
        workspace_id: workspace.workspace_id
      )

    assert {:ok, outcomes} = OutcomeTracker.get_session_outcomes(session.id)
    assert length(outcomes) == 2

    outcome_names = Enum.map(outcomes, &Map.get(&1, "outcome"))
    assert "deploy_success" in outcome_names
    assert "test_pass" in outcome_names
  end

  test "get_session_outcomes returns empty for unknown session" do
    assert {:ok, outcomes} = OutcomeTracker.get_session_outcomes(999_999_999)
    assert outcomes == []
  end

  test "within_window excludes entries with invalid timestamps" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    {:ok, _} =
      OutcomeTracker.record(session.id, :deploy_success,
        agent_id: "window_test",
        workspace_id: workspace.workspace_id
      )

    {:ok, _} =
      ControlKeel.Memory.record(%{
        workspace_id: workspace.workspace_id,
        session_id: session.id,
        record_type: "decision",
        title: "Outcome: Corrupted entry for window_test",
        summary: "Agent window_test outcome with bad timestamp",
        body: "outcome agent window_test",
        tags: ["outcome", "deploy_success", "window_test"],
        source_type: "outcome_tracker",
        source_id: "outcome:#{session.id}:bad_ts",
        metadata: %{
          "outcome" => "deploy_success",
          "reward" => 1.0,
          "label" => "Deploy Succeeded",
          "agent_id" => "window_test",
          "session_id" => session.id,
          "recorded_at" => "not-a-valid-timestamp"
        }
      })

    assert {:ok, score} = OutcomeTracker.get_agent_score("window_test")
    assert score.outcome_count == 1
  end

  test "compute_router_weights returns map" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    OutcomeTracker.record(session.id, :deploy_success,
      agent_id: "rw_1",
      workspace_id: workspace.workspace_id
    )

    OutcomeTracker.record(session.id, :test_pass,
      agent_id: "rw_2",
      workspace_id: workspace.workspace_id
    )

    assert {:ok, weights} = OutcomeTracker.compute_router_weights()
    assert is_map(weights)
  end
end
