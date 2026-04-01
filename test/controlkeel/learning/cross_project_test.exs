defmodule ControlKeel.Learning.CrossProjectTest do
  use ControlKeel.DataCase

  alias ControlKeel.Learning.CrossProject
  import ControlKeel.MissionFixtures

  test "aggregate_findings returns empty for session with no findings" do
    session = session_fixture()
    assert {:ok, result} = CrossProject.aggregate_findings(session.id)
    assert result.total_findings == 0
    assert result.unique_patterns == 0
    assert result.patterns == []
  end

  test "aggregate_findings accepts domain_pack option" do
    session = session_fixture()

    assert {:ok, result} =
             CrossProject.aggregate_findings(session.id, domain_pack: "health")

    assert result.domain_pack == "health"
  end

  test "store_patterns records patterns in memory" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    patterns = [
      %{key: "security:sql_injection:.js", count: 5, severity: 4},
      %{key: "privacy:pii_detected:.ex", count: 3, severity: 2}
    ]

    assert {:ok, results} =
             CrossProject.store_patterns(session.id, patterns,
               workspace_id: workspace.workspace_id,
               domain_pack: "baseline"
             )

    assert length(results) == 2
  end

  test "search_similar returns matching patterns" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    patterns = [
      %{key: "security:xss_unsafe_html:.jsx", count: 7, severity: 4}
    ]

    CrossProject.store_patterns(session.id, patterns,
      domain_pack: "baseline",
      workspace_id: workspace.workspace_id
    )

    assert {:ok, results} = CrossProject.search_similar("xss vulnerability pattern")
    assert is_list(results)
  end

  test "get_frequency_report returns patterns" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    patterns = [
      %{key: "cost:budget_warning:.ex", count: 10, severity: 1}
    ]

    CrossProject.store_patterns(session.id, patterns,
      domain_pack: "baseline",
      workspace_id: workspace.workspace_id
    )

    assert {:ok, results} = CrossProject.get_frequency_report(min_count: 2)
    assert is_list(results)
  end

  test "get_frequency_report with high min_count returns empty" do
    assert {:ok, results} = CrossProject.get_frequency_report(min_count: 100)
    assert results == []
  end
end
