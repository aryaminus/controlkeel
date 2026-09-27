defmodule ControlKeelWeb.ObservabilityEvalsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "save button flashes a summary after saving candidates", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    finding_fixture(%{
      session: session,
      title: "Eval candidate finding",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.evals"
    })

    {:ok, view, _html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/evals")

    view
    |> element("#observability-evals-save")
    |> render_click()

    assert render(view) =~ "Saved 1 candidate(s)"
  end

  test "repeat save flashes a nothing-new message", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    finding_fixture(%{
      session: session,
      title: "Eval candidate finding",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.evals"
    })

    {:ok, view, _html} = live(conn, "/#{org.slug}/workspaces/#{ws.slug}/evals")

    view
    |> element("#observability-evals-save")
    |> render_click()

    view
    |> element("#observability-evals-save")
    |> render_click()

    assert render(view) =~ "Nothing new to save"
  end
end
