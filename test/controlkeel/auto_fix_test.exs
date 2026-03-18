defmodule ControlKeel.AutoFixTest do
  use ControlKeel.DataCase

  alias ControlKeel.AutoFix

  import ControlKeel.MissionFixtures

  test "generate/1 returns guided fixes for the supported rule families" do
    expectations = %{
      "secret.aws_access_key" => "secret_env_migration",
      "secret.hardcoded_credential" => "secret_env_migration",
      "secret.high_entropy_token" => "secret_rotation",
      "security.sql_injection" => "query_parameterization",
      "security.xss_unsafe_html" => "safe_rendering"
    }

    Enum.each(expectations, fn {rule_id, fix_kind} ->
      finding =
        finding_fixture(%{
          rule_id: rule_id,
          metadata: %{"path" => "lib/example.js", "matched_text_redacted" => "abcd...wxyz"}
        })

      fix = AutoFix.generate(finding)

      assert fix["supported"] == true
      assert fix["fix_kind"] == fix_kind
      assert is_binary(fix["summary"])
      assert is_binary(fix["why"])
      assert is_list(fix["steps"])
      assert length(fix["steps"]) >= 2
      assert is_binary(fix["agent_prompt"])
    end)
  end

  test "generate/1 returns a manual-review payload for unsupported findings" do
    finding = finding_fixture(%{rule_id: "review.runtime", category: "review"})

    fix = AutoFix.generate(finding)

    assert fix["supported"] == false
    assert fix["fix_kind"] == nil
    assert fix["agent_prompt"] == nil
    assert fix["requires_human"] == true
    assert fix["summary"] =~ "does not have a guided fix"
  end
end
