defmodule ControlKeel.MCP.Tools.CkFindingTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkFinding
  alias ControlKeel.Memory
  alias ControlKeel.Mission

  import ControlKeel.MissionFixtures

  test "create surfaces prior same-rule precedent" do
    prior_session = session_fixture()
    workspace = Mission.get_session_with_workspace(prior_session.id).workspace
    session = session_fixture(%{workspace: workspace})

    {:ok, _memory} =
      Memory.record(%{
        workspace_id: workspace.id,
        session_id: prior_session.id,
        record_type: "finding",
        title: "Finding dismissed: generated fixture",
        summary:
          "Prior same-rule finding was dismissed after reviewer confirmed it was fixture data.",
        body: "security.sql_injection (critical/rejected)",
        tags: ["security.sql_injection", "rejected", "finding"],
        source_type: "finding",
        source_id: "ck-finding-precedent-fixture",
        metadata: %{"rule_id" => "security.sql_injection", "status" => "rejected"}
      })

    assert {:ok, result} =
             CkFinding.call(%{
               "session_id" => session.id,
               "category" => "security",
               "severity" => "critical",
               "rule_id" => "security.sql_injection",
               "plain_message" => "Potential SQL injection",
               "title" => "SQL injection",
               "decision" => "warn"
             })

    assert Enum.any?(result["precedent"], &(&1["rule_id"] == "security.sql_injection"))
  end
end
