defmodule ControlKeel.CLI.JsonFlagParityTest do
  use ControlKeel.DataCase

  alias ControlKeel.CLI

  import ControlKeel.MissionFixtures

  # Every command whose parser accepts --json must honor it: with json: true
  # the dispatch must produce JSON-parseable output (not human text).
  # Commands pinned here previously parsed --json and silently ignored it.

  defp json_output!(parsed, project_root) do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert 0 == CLI.execute(parsed, project_root: project_root)
      end)

    assert {:ok, _} = Jason.decode(output),
           "expected JSON output, got: #{inspect(String.slice(output, 0, 200))}"

    output
  end

  describe "outcome commands honor --json" do
    test "outcome leaderboard --json" do
      {:ok, parsed} = CLI.parse(["outcome", "leaderboard", "--json"])
      assert Keyword.get(parsed.options, :json) == true
      json_output!(parsed, File.cwd!())
    end

    test "outcome score --json" do
      {:ok, parsed} = CLI.parse(["outcome", "score", "nobody", "--json"])
      json_output!(parsed, File.cwd!())
    end

    test "outcome record --json" do
      session = session_fixture()

      {:ok, parsed} =
        CLI.parse(["outcome", "record", to_string(session.id), "test_pass", "--json"])

      output = json_output!(parsed, File.cwd!())
      assert output =~ "test_pass"
    end
  end

  describe "session/sandbox commands honor --json" do
    test "session list --json" do
      {:ok, parsed} = CLI.parse(["session", "list", "--json"])
      output = json_output!(parsed, File.cwd!())
      assert output =~ "sessions"
    end

    test "sandbox status --json" do
      {:ok, parsed} = CLI.parse(["sandbox", "status", "--json"])
      output = json_output!(parsed, File.cwd!())
      assert output =~ "sandbox"
    end
  end
end
