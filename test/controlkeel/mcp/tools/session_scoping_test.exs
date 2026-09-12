defmodule ControlKeel.MCP.Tools.SessionScopingTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.Tools.CkCopilot
  alias ControlKeel.MCP.Tools.CkExternalService
  alias ControlKeel.MCP.Tools.CkGitStatus
  alias ControlKeel.MCP.Tools.CkOutcomeTracker
  alias ControlKeel.MCP.Tools.CkReviewFeedback
  alias ControlKeel.MCP.Tools.CkReviewStatus
  alias ControlKeel.MCP.Tools.CkRollback
  alias ControlKeel.MCP.Tools.CkSessionDigest

  import ControlKeel.MissionFixtures

  test "copilot rejects unknown sessions instead of operating blindly" do
    assert {:error, {:invalid_arguments, "Session not found"}} =
             CkCopilot.call(%{"session_id" => -999_999, "mode" => "history"})
  end

  test "external service rejects unknown sessions" do
    assert {:error, {:invalid_arguments, "Session not found"}} =
             CkExternalService.call(%{"session_id" => -999_999, "mode" => "summary"})
  end

  test "session digest rejects unknown sessions" do
    assert {:error, {:invalid_arguments, "Session not found"}} =
             CkSessionDigest.call(%{"session_id" => -999_999, "mode" => "list"})
  end

  test "rollback rejects unknown sessions" do
    assert {:error, {:invalid_arguments, "Session not found"}} =
             CkRollback.call(%{"session_id" => -999_999, "mode" => "list"})
  end

  test "outcome tracker rejects unknown sessions in record mode" do
    assert {:error, {:invalid_arguments, "Session not found"}} =
             CkOutcomeTracker.call(%{
               "mode" => "record",
               "session_id" => -999_999,
               "outcome" => "test_pass"
             })
  end

  test "outcome tracker still accepts session-free leaderboard mode" do
    session = session_fixture()

    assert {:ok, %{"mode" => "get_leaderboard"}} =
             CkOutcomeTracker.call(%{
               "mode" => "get_leaderboard",
               "workspace_id" => session.workspace_id
             })
  end

  test "git status normalizes garbage session ids instead of forwarding them" do
    assert {:error, {:invalid_arguments, _}} =
             CkGitStatus.call(%{"session_id" => "not-an-id"})
  end

  test "review status denies cross-session reads when scoped" do
    session_a = session_fixture()
    session_b = session_fixture()
    task = task_fixture(%{session: session_a})

    {:ok, review} =
      ControlKeel.Mission.submit_review(%{
        "task_id" => task.id,
        "submission_body" => "scoped plan",
        "submitted_by" => "test"
      })

    assert {:error, {:invalid_arguments, "Review does not belong to the given session"}} =
             CkReviewStatus.call(%{"review_id" => review.id, "session_id" => session_b.id})

    assert {:ok, %{"review_id" => id}} =
             CkReviewStatus.call(%{"review_id" => review.id, "session_id" => session_a.id})

    assert id == review.id
  end

  test "review feedback denies cross-session decisions when scoped" do
    session_a = session_fixture()
    session_b = session_fixture()
    task = task_fixture(%{session: session_a})

    {:ok, review} =
      ControlKeel.Mission.submit_review(%{
        "task_id" => task.id,
        "submission_body" => "scoped decision",
        "submitted_by" => "test"
      })

    assert {:error, {:invalid_arguments, "Review does not belong to the given session"}} =
             CkReviewFeedback.call(%{
               "review_id" => review.id,
               "decision" => "approved",
               "session_id" => session_b.id
             })

    assert {:ok, %{"status" => "approved"}} =
             CkReviewFeedback.call(%{
               "review_id" => review.id,
               "decision" => "approved",
               "session_id" => session_a.id
             })
  end
end

defmodule ControlKeel.Skills.ClaudeHooksPortabilityTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Skills.ClaudeHooks

  @tag :tmp_dir
  test "generated hooks never invoke a bare controlkeel binary", %{tmp_dir: tmp_dir} do
    paths = ClaudeHooks.write_hooks(tmp_dir)
    assert length(paths) > 0

    violations =
      for %{"path" => path} <- paths,
          line <- path |> File.read!() |> String.split("\n"),
          trimmed = String.trim(line),
          # Bare invocations fail on hosts without controlkeel on PATH;
          # resolver-internal `command -v` probes are the portable pattern.
          String.match?(trimmed, ~r/(^|[`$"'(;|&]|\s)controlkeel(\s|$)/),
          not String.contains?(trimmed, "command -v controlkeel"),
          not String.contains?(line, "ck_bin"),
          do: {Path.basename(path), trimmed}

    assert violations == [],
           "hooks invoking bare `controlkeel`: #{inspect(violations, pretty: true)}"
  end

  @tag :tmp_dir
  test "generated hooks resolve the binary portably", %{tmp_dir: tmp_dir} do
    paths = ClaudeHooks.write_hooks(tmp_dir)

    for %{"path" => path} <- paths do
      content = File.read!(path)

      if String.contains?(content, "context --json") or
           String.contains?(content, "review plan submit") do
        assert content =~ "CONTROLKEEL_BIN",
               "#{Path.basename(path)} shells out without a CONTROLKEEL_BIN fallback"
      end
    end
  end
end
