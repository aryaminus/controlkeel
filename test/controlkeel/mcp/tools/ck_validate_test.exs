defmodule ControlKeel.MCP.Tools.CkValidateTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Finding

  import ControlKeel.MissionFixtures

  test "persists findings when session_id is present" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    assert {:ok, result} =
             CkValidate.call(%{
               "content" =>
                 ~s(query = "SELECT * FROM users WHERE email = '" <> params["email"] <> "' OR 1=1 --"),
               "path" => "lib/query_builder.js",
               "kind" => "code",
               "session_id" => session.id,
               "task_id" => task.id
             })

    assert result["decision"] == "block"

    persisted_session = Mission.get_session_with_details!(session.id)

    finding =
      Enum.find(
        persisted_session.findings,
        &(&1.rule_id == "security.sql_injection" and
            &1.metadata["path"] == "lib/query_builder.js")
      )

    assert finding
    assert finding.status == "blocked"
    assert finding.metadata["kind"] == "code"
    assert finding.metadata["task_id"] == task.id
    assert finding.metadata["scanner"] == "fast_path"
    assert finding.metadata["matched_text_redacted"] == "[redacted]"
  end

  test "returns findings without persistence when session_id is absent" do
    starting_count = Repo.aggregate(Finding, :count, :id)

    assert {:ok, result} =
             CkValidate.call(%{
               "content" =>
                 ~s(query = "SELECT * FROM users WHERE email = '" <> params["email"] <> "' OR 1=1 --"),
               "path" => "lib/query_builder.js",
               "kind" => "code"
             })

    assert result["decision"] == "block"
    assert Repo.aggregate(Finding, :count, :id) == starting_count
  end

  test "returns budget warnings when a session is near its cap" do
    session = session_fixture(%{budget_cents: 1_000, spent_cents: 850})

    assert {:ok, result} =
             CkValidate.call(%{
               "content" => "const ready = true;",
               "kind" => "code",
               "session_id" => session.id
             })

    assert result["allowed"] == true
    assert result["decision"] == "warn"
    assert Enum.any?(result["findings"], &(&1["rule_id"] == "cost.budget_warning"))
  end
end
