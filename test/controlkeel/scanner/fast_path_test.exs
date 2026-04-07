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

  test "loads new government domain rules when the pack is selected" do
    result =
      FastPath.scan(%{
        "content" => "Repo.query!(\"DELETE FROM permit_records WHERE inserted_at < NOW()\")",
        "path" => "lib/gov/records_cleanup.ex",
        "kind" => "code",
        "domain_pack" => "government"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "government.records_retention_bypass"))
    assert result.decision == "block"
  end

  test "loads new ecommerce domain rules when the pack is selected" do
    result =
      FastPath.scan(%{
        "content" => ~S|Logger.info("card_number=#{order.card_number} cvv=#{order.cvv}")|,
        "path" => "lib/shop/checkout_logger.ex",
        "kind" => "code",
        "domain_pack" => "ecommerce"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "ecommerce.payment_logging"))
    assert result.decision == "block"
  end

  test "blocks destructive repo-wide shell cleanup commands with recovery guidance" do
    result =
      FastPath.scan(%{
        "content" => "git checkout -- . && git clean -fd",
        "path" => "scripts/cleanup.sh",
        "kind" => "shell"
      })

    assert result.decision == "block"

    assert Enum.any?(
             result.findings,
             &(&1.rule_id == "destructive.shell.git_checkout_repo_wide")
           )

    clean_finding =
      Enum.find(result.findings, &(&1.rule_id == "destructive.shell.git_clean_force"))

    assert clean_finding
    assert clean_finding.category == "destructive_operation"
    assert clean_finding.metadata["checkpoint_recommended"] == true
    assert is_binary(clean_finding.metadata["recovery_guidance"])
  end

  test "does not flag path-scoped git restore commands as repo-wide destructive cleanup" do
    result =
      FastPath.scan(%{
        "content" => "git restore lib/controlkeel/scanner/fast_path.ex",
        "path" => "scripts/recover.sh",
        "kind" => "shell"
      })

    refute Enum.any?(result.findings, &String.starts_with?(&1.rule_id, "destructive.shell."))
  end
end
