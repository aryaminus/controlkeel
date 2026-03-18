defmodule ControlKeel.Scanner.EntropyTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Scanner.Entropy

  setup do
    {:ok, rules: PackLoader.load!("baseline")}
  end

  test "detects high-entropy secret-like tokens", %{rules: rules} do
    token = "N4f8qP2mX9vR7kL3cT6wH1sD0bY5uJ8"

    findings = Entropy.detect(token, %{"path" => ".env", "kind" => "config"}, rules)

    assert Enum.any?(findings, &(&1.rule_id == "secret.high_entropy_token"))

    finding = Enum.find(findings, &(&1.rule_id == "secret.high_entropy_token"))
    assert finding.decision == "block"
    assert finding.metadata["matcher"] == "entropy"
    assert finding.metadata["matched_text_redacted"] =~ "N4f8"
    assert finding.metadata["entropy"] >= 4.2
  end

  test "ignores low-entropy benign strings", %{rules: rules} do
    content = "DATABASE_URL=postgres://localhost/controlkeel_dev"

    findings = Entropy.detect(content, %{"path" => ".env", "kind" => "config"}, rules)

    refute Enum.any?(findings, &(&1.rule_id == "secret.high_entropy_token"))
  end
end
