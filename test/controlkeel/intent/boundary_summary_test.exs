defmodule ControlKeel.Intent.BoundarySummaryTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Intent

  import ControlKeel.IntentFixtures

  test "builds a production boundary summary from the execution brief and compiler answers" do
    brief = execution_brief_fixture()
    summary = Intent.boundary_summary(brief)

    assert summary["risk_tier"] == "critical"
    assert summary["budget_note"] == "$40/month to start"
    assert summary["data_summary"] == "Patient names, insurance notes, and scheduling details."
    assert summary["compliance"] == ["HIPAA", "HITECH", "OWASP Top 10"]
    assert summary["constraints"] == ["Approval before deploy"]

    assert summary["open_questions"] == [
             "Which EHR integration should the first release support?"
           ]

    assert summary["launch_window"] == "Internal pilot before broader rollout"

    assert summary["next_step"] ==
             "Lock the architecture, hosting boundary, and approval flow before code generation."

    assert summary["execution_posture"]["exploration_surface"] == "virtual_workspace"
    assert summary["execution_posture"]["api_execution_surface"] == "typed_runtime"
    assert summary["execution_posture"]["shell_role"] == "broad_fallback_only"
  end

  test "normalizes blank or comma-separated constraints into a short list" do
    brief =
      execution_brief_fixture(
        compiler: %{
          "interview_answers" => %{
            "constraints" => "Local-first deploy,\napproval before production,  "
          }
        }
      )

    assert Intent.boundary_summary(brief)["constraints"] == [
             "Local-first deploy",
             "approval before production"
           ]

    empty =
      execution_brief_fixture(compiler: %{"interview_answers" => %{"constraints" => "   "}})

    assert Intent.boundary_summary(empty)["constraints"] == []
  end

  test "returns an empty nil-safe summary when the brief or compiler metadata is missing" do
    assert Intent.boundary_summary(nil) == %{
             "risk_tier" => nil,
             "budget_note" => nil,
             "data_summary" => nil,
             "compliance" => [],
             "constraints" => [],
             "open_questions" => [],
             "launch_window" => nil,
             "next_step" => nil,
             "execution_posture" => %{
               "exploration_surface" => "virtual_workspace",
               "api_execution_surface" => "typed_runtime_or_shell",
               "mutation_surface" => "shell_sandbox",
               "shell_role" => "fallback",
               "clearance_focus" => ["file_write", "network", "deploy", "secrets"],
               "rationale" =>
                 "Prefer read-only discovery first, keep large tool and API interactions in typed runtimes when available, and treat shell as the broad fallback surface for mutation and execution."
             }
           }

    assert Intent.boundary_summary(%{"risk_tier" => "high"})["constraints"] == []
  end
end
