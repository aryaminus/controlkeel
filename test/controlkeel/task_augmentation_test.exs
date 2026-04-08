defmodule ControlKeel.TaskAugmentationTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission
  alias ControlKeel.TaskAugmentation

  test "builds a derived contextual brief from task, findings, and workspace context" do
    session =
      session_fixture(%{objective: "Stabilize the authentication flow", risk_tier: "high"})

    task =
      task_fixture(%{session: session, status: "in_progress", title: "Fix auth session race"})

    finding_fixture(%{
      session: session,
      status: "blocked",
      category: "security",
      title: "Session fixation risk",
      rule_id: "security.session_fixation",
      plain_message: "Regenerate the session token during login."
    })

    session = Mission.get_session_context(session.id)

    workspace_context = %{
      "available" => true,
      "instruction_files" => [%{"path" => "AGENTS.md"}],
      "key_files" => [%{"path" => "mix.exs"}],
      "design_drift" => %{
        "recent_hotspots" => [%{"path" => "lib/controlkeel_web/live/onboarding_live.ex"}],
        "large_files" => []
      }
    }

    augmentation = TaskAugmentation.build(session, task, workspace_context)

    assert augmentation["available"] == true
    assert augmentation["task_title"] == "Fix auth session race"
    assert "AGENTS.md" in augmentation["likely_paths"]
    assert "mix.exs" in augmentation["likely_paths"]
    assert "active_findings" in augmentation["evidence_sources"]
    assert is_binary(augmentation["augmented_brief"])
    assert augmentation["active_finding_count"] == 1
    assert Enum.any?(augmentation["validation_focus"], &String.contains?(&1, "blocked"))
  end
end
