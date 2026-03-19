defmodule ControlKeel.Scanner.FastPathTest do
  use ControlKeel.DataCase

  alias ControlKeel.Scanner.FastPath

  import ControlKeel.MissionFixtures

  test "loads domain-specific rules when domain_pack is provided directly" do
    result =
      FastPath.scan(%{
        "content" => "def score(candidate), do: reject(candidate.age > 50)",
        "path" => "lib/hr/ranker.ex",
        "kind" => "code",
        "domain_pack" => "hr"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "hr.discriminatory_criteria"))
    assert result.decision == "block"
  end

  test "loads domain-specific rules from the governed session context" do
    session = session_fixture(%{execution_brief: %{"domain_pack" => "legal"}})

    result =
      FastPath.scan(%{
        "content" => ~S|Logger.info("privileged memo=#{matter.privileged_memo}")|,
        "path" => "lib/legal/audit.ex",
        "kind" => "code",
        "session_id" => session.id
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "legal.privileged_content_logging"))
    assert result.decision == "block"
  end

  test "baseline rules still apply alongside domain-specific rules" do
    result =
      FastPath.scan(%{
        "content" => ~s(export CRM_KEY="AKIAIOSFODNN7EXAMPLE"),
        "path" => "scripts/setup.sh",
        "kind" => "shell",
        "domain_pack" => "sales"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "secret.aws_access_key"))
    assert result.decision == "block"
  end
end
