defmodule ControlKeel.MCP.Tools.CkReviewSubmitTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkReviewSubmit

  import ControlKeel.MissionFixtures

  @tag :tmp_dir
  test "explicit project_root pins the target session instead of inheriting cwd", %{
    tmp_dir: tmp_dir
  } do
    session = session_fixture()

    {:ok, result} =
      CkReviewSubmit.call(%{
        "session_id" => session.id,
        "submission_body" => "Plan pinned to an explicit project root",
        "submitted_by" => "test",
        "project_root" => tmp_dir
      })

    assert result["session_id"] == session.id

    stored = ControlKeel.Mission.get_review!(result["review_id"])
    assert get_in(stored.metadata, ["runtime_context", "project_root"]) == tmp_dir
  end

  test "omitted project_root falls back to File.cwd!/0" do
    session = session_fixture()

    {:ok, result} =
      CkReviewSubmit.call(%{
        "session_id" => session.id,
        "submission_body" => "Plan without an explicit project root",
        "submitted_by" => "test"
      })

    assert result["session_id"] == session.id

    stored = ControlKeel.Mission.get_review!(result["review_id"])

    assert get_in(stored.metadata, ["runtime_context", "project_root"]) ==
             System.get_env("CONTROLKEEL_PROJECT_ROOT") || File.cwd!()
  end
end
