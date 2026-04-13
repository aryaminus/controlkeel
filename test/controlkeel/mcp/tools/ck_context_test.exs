defmodule ControlKeel.MCP.Tools.CkContextTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkContext
  alias ControlKeel.Mission
  alias ControlKeel.Platform

  import ControlKeel.MissionFixtures

  test "returns task assurance with verification and context integrity" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    assert {:ok, _run} = Platform.claim_task(task.id)

    assert {:ok, _checks} =
             Platform.record_task_checks(task.id, nil, [
               %{
                 check_type: "validation",
                 status: "passed",
                 summary: "Validation passed",
                 payload: %{"source" => "fixture"}
               }
             ])

    assert {:ok, _updated} =
             Mission.attach_task_runtime_context(task.id, %{
               "partial_reads" => [%{"path" => "lib/huge.ex", "truncated_at_line" => 2000}]
             })

    assert {:ok, done_task} = Mission.update_task(Mission.get_task!(task.id), %{status: "done"})
    assert {:ok, _proof} = Mission.generate_proof_bundle(done_task.id)

    assert {:ok, result} =
             CkContext.call(%{"session_id" => session.id, "task_id" => done_task.id})

    assert result["current_task"]["assurance"]["check_summary"]["passed"] == 1
    assert result["current_task"]["assurance"]["context_integrity"]["status"] == "degraded"

    assert "task_checks" in result["current_task"]["assurance"]["verification"][
             "evidence_sources"
           ]
  end
end
