defmodule ControlKeelWeb.ObservabilityRecommendationsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Repo

  test "recommendation links stay inside the visited workspace", %{conn: conn} do
    {org, ws, session} = org_bound_session_fixture()

    finding_fixture(%{
      session: session,
      title: "Recommendation link finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.recommendation_link"
    })

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "codex-cli",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               input_tokens: 1_000,
               output_tokens: 250,
               estimated_cost_cents: 10,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    {:ok, _view, html} =
      live(conn, "/#{org.slug}/workspaces/#{ws.slug}/observability/recommendations")

    prefix = "/#{org.slug}/workspaces/#{ws.slug}"

    # <.link navigate> renders as href.
    assert html =~ ~s(href="#{prefix}/observability/problems")
    assert html =~ ~s(href="#{prefix}/observability/costs")
    assert html =~ ~s(href="#{prefix}/observability")

    # No bare global links remain; /proofs is not an observability page.
    refute html =~ ~s(href="/observability")
    refute html =~ ~s(href="/observability/problems")
    refute html =~ ~s(href="/observability/costs")
    assert html =~ ~s(href="/proofs")
  end
end
