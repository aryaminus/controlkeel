defmodule ControlKeelWeb.FindingsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  test "findings browser supports filter combinations and mission links", %{conn: conn} do
    alpha = session_fixture(%{title: "Alpha mission"})
    bravo = session_fixture(%{title: "Bravo mission"})

    target =
      finding_fixture(%{
        session: alpha,
        title: "Alpha SQL finding",
        rule_id: "security.sql_injection",
        category: "security",
        severity: "high",
        status: "open",
        plain_message: "Alpha query issue",
        metadata: %{"path" => "lib/query_builder.js"}
      })

    _other =
      finding_fixture(%{
        session: bravo,
        title: "Bravo XSS finding",
        rule_id: "security.xss_unsafe_html",
        category: "security",
        severity: "medium",
        status: "approved",
        plain_message: "Bravo browser issue"
      })

    {:ok, view, html} =
      live(
        conn,
        ~p"/findings?#{%{q: "Alpha", severity: "high", status: "open", category: "security", session_id: alpha.id}}"
      )

    assert html =~ "Findings browser"
    assert html =~ "Alpha SQL finding"
    refute html =~ "Bravo XSS finding"
    assert has_element?(view, "a[href=\"/missions/#{alpha.id}\"]", alpha.title)

    patched =
      render_change(
        form(view, "form",
          filters: %{
            "q" => "Bravo",
            "severity" => "",
            "status" => "",
            "category" => "",
            "session_id" => ""
          }
        )
      )

    assert patched =~ "Findings browser"
    assert_patch(view, ~p"/findings?#{%{q: "Bravo"}}")

    _ = target
  end

  test "findings browser paginates and updates status actions live", %{conn: conn} do
    session = session_fixture()

    Enum.each(1..21, fn index ->
      finding_fixture(%{
        session: session,
        title: "Paged finding #{index}",
        rule_id: "security.sample.#{index}",
        severity: "low",
        category: "ops",
        status: "open"
      })
    end)

    actionable =
      finding_fixture(%{
        session: session,
        title: "Actionable finding",
        rule_id: "security.sql_injection",
        severity: "high",
        category: "security",
        status: "open",
        metadata: %{"path" => "lib/query_builder.js"}
      })

    rejectable =
      finding_fixture(%{
        session: session,
        title: "Rejectable finding",
        rule_id: "security.xss_unsafe_html",
        severity: "medium",
        category: "security",
        status: "open"
      })

    {:ok, view, html} = live(conn, ~p"/findings")
    assert html =~ "Page 1 of 2"
    assert has_element?(view, "a[href*=\"page=2\"]", "Next page")

    render_click(
      element(view, "button[phx-click=\"approve\"][phx-value-id=\"#{actionable.id}\"]")
    )

    assert render(view) =~ "Finding approved."
    assert Mission.get_finding!(actionable.id).status == "approved"

    render_click(element(view, "button[phx-click=\"reject\"][phx-value-id=\"#{rejectable.id}\"]"))
    assert Mission.get_finding!(rejectable.id).status == "rejected"
  end

  test "findings browser renders the guided fix panel", %{conn: conn} do
    session = session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        title: "SQL finding",
        rule_id: "security.sql_injection",
        severity: "high",
        category: "security",
        metadata: %{"path" => "lib/query_builder.js", "matched_text_redacted" => "OR 1... --"}
      })

    {:ok, view, _html} = live(conn, ~p"/findings")

    detail_html =
      render_click(
        element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{finding.id}\"]")
      )

    assert detail_html =~ "Guided fix"
    assert detail_html =~ "parameterized queries"
    assert detail_html =~ "Copy fix prompt"
  end
end
