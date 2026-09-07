defmodule ControlKeelWeb.SessionTranscriptLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission.SessionTranscript

  test "session transcript lists the recent events for the session", %{conn: conn} do
    session = session_fixture()

    assert {:ok, _event} =
             SessionTranscript.record(%{
               session_id: session.id,
               event_type: "tool_call",
               actor: "opencode",
               summary: "Ran ck_validate"
             })

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/transcript")

    assert html =~ "Ran ck_validate"
    assert html =~ "tool_call"
    assert html =~ "opencode"
    assert html =~ "Family"
  end

  test "session transcript lists events recorded at session creation", %{conn: conn} do
    session = session_fixture()

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/transcript")

    assert html =~ "session.created"
  end

  test "session transcript refreshes when new events are recorded", %{conn: conn} do
    session = session_fixture()

    assert {:ok, _event} =
             SessionTranscript.record(%{
               session_id: session.id,
               event_type: "review.submitted",
               actor: "agent",
               summary: "Submitted plan review"
             })

    {:ok, view, html} = live(conn, ~p"/sessions/#{session.id}/transcript")
    assert html =~ "Submitted plan review"

    assert {:ok, _event} =
             SessionTranscript.record(%{
               session_id: session.id,
               event_type: "finding.created",
               actor: "harness",
               summary: "Created a high finding"
             })

    send(view.pid, :refresh)
    refreshed_html = render(view)

    assert refreshed_html =~ "Created a high finding"
  end

  test "session transcript lists all events, not just the most recent ten", %{conn: conn} do
    session = session_fixture()

    for index <- 1..11 do
      assert {:ok, _event} =
               SessionTranscript.record(%{
                 session_id: session.id,
                 event_type: "tool_call",
                 actor: "agent",
                 summary: "Event #{index}",
                 payload: %{},
                 metadata: %{}
               })
    end

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/transcript")

    for index <- 1..11 do
      assert html =~ "Event #{index}"
    end
  end

  test "session transcript redirects when the session does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, ~p"/sessions/999999/transcript")
  end
end
