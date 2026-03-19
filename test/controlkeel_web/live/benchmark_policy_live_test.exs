defmodule ControlKeelWeb.BenchmarkPolicyLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.PolicyTrainingFixtures
  import Phoenix.LiveViewTest

  test "renders a policy artifact and allows archive", %{conn: conn} do
    artifact =
      policy_artifact_fixture(%{
        artifact_type: "router",
        status: "candidate",
        metrics: %{"gates" => %{"eligible" => true, "reasons" => []}}
      })

    {:ok, view, html} = live(conn, ~p"/benchmarks/policies/#{artifact.id}")

    assert html =~ "Policy artifact"
    assert has_element?(view, "#policy-detail")
    assert has_element?(view, "#policy-promote")
    assert has_element?(view, "#policy-archive")

    render_click(element(view, "#policy-archive"))
    assert render(view) =~ "Artifact archived."
  end
end
