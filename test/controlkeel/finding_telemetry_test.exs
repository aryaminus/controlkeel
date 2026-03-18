defmodule ControlKeel.FindingTelemetryTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  setup %{conn: conn} do
    handler_id = "controlkeel-finding-telemetry-#{inspect(self())}"

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :telemetry.attach_many(
      handler_id,
      [
        [:controlkeel, :finding, :approved],
        [:controlkeel, :finding, :rejected],
        [:controlkeel, :autofix, :viewed],
        [:controlkeel, :autofix, :copied]
      ],
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      self()
    )

    {:ok, conn: conn}
  end

  test "finding approval and rejection emit telemetry", %{conn: _conn} do
    finding = finding_fixture()

    assert {:ok, approved} = Mission.approve_finding(finding)

    assert_receive {:telemetry, [:controlkeel, :finding, :approved], %{count: 1}, metadata}
    assert metadata.finding_id == approved.id
    assert metadata.status == "approved"

    assert {:ok, rejected} = Mission.reject_finding(approved, "Manual override")

    assert_receive {:telemetry, [:controlkeel, :finding, :rejected], %{count: 1}, metadata}
    assert metadata.finding_id == rejected.id
    assert metadata.status == "rejected"
  end

  test "autofix view and copy emit telemetry", %{conn: conn} do
    session = session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        rule_id: "security.sql_injection",
        title: "SQL finding",
        metadata: %{"path" => "lib/query_builder.js", "matched_text_redacted" => "OR 1... --"}
      })

    {:ok, view, _html} = live(conn, ~p"/findings")

    render_click(element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{finding.id}\"]"))

    assert_receive {:telemetry, [:controlkeel, :autofix, :viewed], %{count: 1}, metadata}
    assert metadata.finding_id == finding.id
    assert metadata.rule_id == "security.sql_injection"
    assert metadata.supported == true

    render_click(
      element(view, "button[phx-click=\"copy_fix_prompt\"][phx-value-id=\"#{finding.id}\"]")
    )

    assert_receive {:telemetry, [:controlkeel, :autofix, :copied], %{count: 1}, metadata}
    assert metadata.finding_id == finding.id
    assert_push_event(view, "copy-to-clipboard", %{text: _text})
  end
end
