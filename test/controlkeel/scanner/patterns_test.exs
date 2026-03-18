defmodule ControlKeel.Scanner.PatternsTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Scanner.Patterns

  setup do
    {:ok, rules: PackLoader.load!("baseline")}
  end

  test "detects AWS-style access keys", %{rules: rules} do
    content = ~s(export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE")

    findings = Patterns.detect(content, %{"path" => "deploy.sh", "kind" => "shell"}, rules)

    assert Enum.any?(findings, &(&1.rule_id == "secret.aws_access_key"))

    finding = Enum.find(findings, &(&1.rule_id == "secret.aws_access_key"))
    assert finding.decision == "block"
    assert finding.location == %{"path" => "deploy.sh", "kind" => "shell"}
    assert finding.metadata["matched_text_redacted"] =~ "AKIA"
  end

  test "detects basic SQL injection patterns", %{rules: rules} do
    content =
      ~s(query = "SELECT * FROM users WHERE email = '" <> params["email"] <> "' OR 1=1 --")

    findings = Patterns.detect(content, %{"path" => "user_query.js", "kind" => "code"}, rules)

    assert Enum.any?(findings, &(&1.rule_id == "security.sql_injection"))
  end

  test "detects unsafe HTML and script injection patterns", %{rules: rules} do
    content = ~s(document.body.innerHTML = userSuppliedMarkup)

    findings = Patterns.detect(content, %{"path" => "app.js", "kind" => "code"}, rules)

    assert Enum.any?(findings, &(&1.rule_id == "security.xss_unsafe_html"))
  end

  test "does not flag benign content", %{rules: rules} do
    content = ~s(const title = "Quarterly marketing report";)

    findings = Patterns.detect(content, %{"path" => "report.js", "kind" => "code"}, rules)

    assert findings == []
  end
end
