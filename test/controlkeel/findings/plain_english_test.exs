defmodule ControlKeel.Findings.PlainEnglishTest do
  use ControlKeel.DataCase

  alias ControlKeel.Findings.PlainEnglish

  test "translates sql_injection finding" do
    finding = %{
      "rule_id" => "security.sql_injection",
      "category" => "security",
      "severity" => "critical"
    }

    result = PlainEnglish.translate(finding)

    assert result.title == "Database attack vulnerability"
    assert is_binary(result.explanation)
    assert is_binary(result.fix)
    assert is_binary(result.risk_if_ignored)
    assert result.category_explanation =~ "security"
    assert result.severity_explanation =~ "urgent"
  end

  test "translates hardcoded_secret finding" do
    result =
      PlainEnglish.translate(%{
        "rule_id" => "security.hardcoded_secret",
        "category" => "security",
        "severity" => "high"
      })

    assert result.title == "Password or key left in code"
    assert result.fix =~ "environment variable"
  end

  test "translates budget_warning finding" do
    result =
      PlainEnglish.translate(%{
        "rule_id" => "cost.budget_warning",
        "category" => "cost",
        "severity" => "medium"
      })

    assert result.title == "Spending approaching limit"
    assert result.category_explanation =~ "cost"
  end

  test "translates pii_detected finding" do
    result =
      PlainEnglish.translate(%{
        "rule_id" => "privacy.pii_detected",
        "category" => "privacy",
        "severity" => "high"
      })

    assert result.title == "Personal information exposed"
    assert result.fix =~ "Encrypt"
  end

  test "handles unknown rule_id with humanized fallback" do
    result =
      PlainEnglish.translate(%{
        "rule_id" => "custom.unknown_rule",
        "category" => "quality",
        "severity" => "low"
      })

    assert result.title == "Unknown rule"
    assert is_binary(result.explanation)
    assert is_nil(result.fix)
  end

  test "uses original_message for unknown rules when available" do
    result =
      PlainEnglish.translate(%{
        "rule_id" => "custom.test",
        "category" => "hygiene",
        "severity" => "low",
        "plain_message" => "Something is wrong here"
      })

    assert result.explanation == "Something is wrong here"
  end

  test "translate_list translates multiple findings" do
    findings = [
      %{
        "rule_id" => "security.sql_injection",
        "category" => "security",
        "severity" => "critical"
      },
      %{"rule_id" => "cost.budget_guard", "category" => "cost", "severity" => "high"}
    ]

    results = PlainEnglish.translate_list(findings)
    assert length(results) == 2
    assert Enum.all?(results, &Map.has_key?(&1, :title))
  end

  test "supports atom keys in finding maps" do
    result =
      PlainEnglish.translate(%{
        rule_id: "security.xss_unsafe_html",
        category: "security",
        severity: "high"
      })

    assert result.title == "Unsafe content display"
  end

  test "all category explanations are present" do
    for category <- [
          "security",
          "privacy",
          "compliance",
          "cost",
          "delivery",
          "hygiene",
          "fraud",
          "safety",
          "quality",
          "logic",
          "dependencies"
        ] do
      result =
        PlainEnglish.translate(%{
          "rule_id" => "custom.test",
          "category" => category,
          "severity" => "medium"
        })

      assert is_binary(result.category_explanation)
    end
  end

  test "all severity explanations are present" do
    for severity <- ["critical", "high", "medium", "low"] do
      result =
        PlainEnglish.translate(%{
          "rule_id" => "custom.test",
          "category" => "security",
          "severity" => severity
        })

      assert is_binary(result.severity_explanation)
    end
  end
end
