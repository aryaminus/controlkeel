defmodule ControlKeel.SessionTranscriptTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.SessionTranscript

  test "record/1 clips structured payloads and groups transcript summaries" do
    session = session_fixture()
    task = task_fixture(%{session: session})

    long_summary = String.duplicate("s", 400)
    long_body = String.duplicate("b", 3_000)
    long_payload = String.duplicate("p", 5_000)

    assert {:ok, _event} =
             SessionTranscript.record(%{
               session_id: session.id,
               task_id: task.id,
               event_type: "task.updated",
               actor: "codex",
               summary: long_summary,
               body: long_body,
               payload: %{
                 "long_text" => long_payload,
                 "captured_at" => DateTime.utc_now()
               }
             })

    assert {:ok, _event} =
             SessionTranscript.record(%{
               session_id: session.id,
               event_type: "review.submitted",
               actor: "codex",
               summary: "Submitted review"
             })

    [latest | _rest] = SessionTranscript.recent_events(session.id)
    summary = SessionTranscript.summary(session.id)

    assert latest["event_type"] == "review.submitted"

    task_event =
      SessionTranscript.recent_events(session.id)
      |> Enum.find(&(&1["event_type"] == "task.updated"))

    assert String.length(task_event["summary"]) <= 280
    assert String.length(task_event["body"]) <= 2_048
    assert String.length(task_event["payload"]["long_text"]) <= 4_096
    assert is_binary(task_event["payload"]["captured_at"])
    assert summary["total_events"] >= 2
    assert Enum.any?(summary["families"], &(&1["family"] == "task"))
    assert Enum.any?(summary["families"], &(&1["family"] == "review"))
  end
end
