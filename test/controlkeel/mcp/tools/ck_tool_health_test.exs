defmodule ControlKeel.MCP.Tools.CkToolHealthTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkToolHealth
  alias ControlKeel.Mission

  import ControlKeel.MissionFixtures

  test "returns governance coverage for a session with no activity" do
    session = session_fixture()

    assert {:ok, result} = CkToolHealth.call(%{"session_id" => session.id})

    assert result["workspace_id"] == session.workspace_id
    assert result["source_session_id"] == session.id
    assert result["sessions_analyzed"] >= 1
    assert result["total_area_count"] == 5
    assert is_float(result["coverage_score"])
    assert is_list(result["areas"])
    assert is_list(result["recommendations"])
    assert is_list(result["load_bearing_areas"])
    assert is_list(result["unused_areas"])

    area_names = Enum.map(result["areas"], & &1["area"])
    assert "validation" in area_names
    assert "review_gates" in area_names
    assert "budget_tracking" in area_names
    assert "memory_retention" in area_names
    assert "goal_tracking" in area_names
  end

  test "marks validation as load_bearing when findings exist" do
    session = session_fixture()

    for _ <- 1..12 do
      finding_fixture(%{session: session})
    end

    assert {:ok, result} = CkToolHealth.call(%{"session_id" => session.id})

    validation_area = Enum.find(result["areas"], &(&1["area"] == "validation"))
    assert validation_area["health"] == "load_bearing"
    assert validation_area["count"] >= 12
    assert validation_area["detail"]["open"] >= 0
  end

  test "marks review_gates as load_bearing when enough reviews exist" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    for _ <- 1..6 do
      review_fixture(%{session: session, task: task})
    end

    assert {:ok, result} = CkToolHealth.call(%{"session_id" => session.id})

    review_area = Enum.find(result["areas"], &(&1["area"] == "review_gates"))
    assert review_area["health"] == "load_bearing"
    assert review_area["count"] >= 6
  end

  test "marks unused areas as unused and emits recommendations" do
    session = session_fixture()

    assert {:ok, result} = CkToolHealth.call(%{"session_id" => session.id})

    unused = result["unused_areas"]
    assert length(unused) > 0

    assert length(result["recommendations"]) ==
             length(unused) + length(Enum.filter(result["areas"], &(&1["health"] == "low_usage")))
  end

  test "coverage_score is 1.0 when all areas active" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    for _ <- 1..12, do: finding_fixture(%{session: session})
    for _ <- 1..6, do: review_fixture(%{session: session, task: task})
    for _ <- 1..6, do: memory_record_fixture(%{session: session})

    {:ok, _} =
      Mission.create_invocation(%{
        source: "mcp",
        tool: "ck_budget",
        estimated_cost_cents: 0,
        decision: "allow",
        metadata: %{},
        session_id: session.id
      })

    for _ <- 1..5 do
      {:ok, _} =
        Mission.create_invocation(%{
          source: "mcp",
          tool: "ck_budget",
          estimated_cost_cents: 0,
          decision: "allow",
          metadata: %{},
          session_id: session.id
        })
    end

    assert {:ok, result} = CkToolHealth.call(%{"session_id" => session.id})
    assert result["coverage_score"] > 0.5
  end

  test "accepts string session_id" do
    session = session_fixture()
    id_string = Integer.to_string(session.id)

    assert {:ok, result} = CkToolHealth.call(%{"session_id" => id_string})
    assert result["source_session_id"] == session.id
  end

  test "returns not_found for unknown session" do
    assert {:error, :not_found} = CkToolHealth.call(%{"session_id" => 999_999_999})
  end

  test "returns error for missing session_id" do
    assert {:error, {:invalid_arguments, msg}} = CkToolHealth.call(%{})
    assert msg =~ "session_id"
  end

  test "respects session_limit" do
    session = session_fixture()

    assert {:ok, result} =
             CkToolHealth.call(%{"session_id" => session.id, "session_limit" => "1"})

    assert result["sessions_analyzed"] >= 1
  end
end
