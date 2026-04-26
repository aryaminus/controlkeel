defmodule ControlKeelWeb.ReviewLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission

  test "review live renders alignment context from plan refinement", %{conn: conn} do
    session = session_fixture()

    task =
      task_fixture(%{session: session, status: "queued", title: "Collaborative review packet"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "plan_phase" => "implementation_plan",
               "submission_body" => "Implementation plan with human context",
               "research_summary" => "Mapped review and plan-refinement seams.",
               "alignment_context" => [
                 "PM confirmed the rollout should stay behind approval gates.",
                 "Support asked for reviewer-visible rollback notes before merge."
               ],
               "consulted_roles" => ["PM", "Support", "Security"],
               "options_considered" => ["Patch review packet", "Create separate planning surface"],
               "selected_option" => "Patch review packet",
               "rejected_options" => ["Create separate planning surface"],
               "implementation_steps" => [
                 "Persist alignment fields",
                 "Render them in browser review"
               ],
               "validation_plan" => ["mix test test/controlkeel_web/live/review_live_test.exs"]
             })

    {:ok, _view, html} = live(conn, ~p"/reviews/#{review.id}")

    assert html =~ "Human context gathered before execution"
    assert html =~ "PM confirmed the rollout should stay behind approval gates."
    assert html =~ "Support asked for reviewer-visible rollback notes before merge."
    assert html =~ "PM"
    assert html =~ "Support"
    assert html =~ "Security"
  end
end
