defmodule ControlKeel.Governance.SocketTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Governance.Socket

  test "normalizes socket issues into dependency review issues" do
    report = %{
      "issues" => [
        %{
          "package" => "event-stream",
          "severity" => "critical",
          "summary" => "Compromised package",
          "manifest_path" => "package-lock.json",
          "id" => "socket-alert-001"
        }
      ]
    }

    assert {:ok, %{"issues" => [issue]}} = Socket.dependency_review(report)
    assert issue["package"] == "event-stream"
    assert issue["severity"] == "critical"
    assert issue["summary"] == "Compromised package"
    assert issue["manifest_path"] == "package-lock.json"
    assert issue["rule_id"] == "dependencies.socket.alert"
    assert issue["advisory_id"] == "socket-alert-001"
    assert issue["source"] == "socket"
  end

  test "returns error when no issue collection exists" do
    assert {:error, "Socket report did not contain dependency issues."} =
             Socket.dependency_review(%{"meta" => %{"ok" => true}})
  end
end
