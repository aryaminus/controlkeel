defmodule ControlKeel.PIIDetectorTest do
  use ExUnit.Case, async: true

  alias ControlKeel.PIIDetector

  describe "scan/2" do
    test "detects credit card numbers" do
      text = "My card is 4532-1234-5678-9012"
      {:ok, result} = PIIDetector.scan(text)

      assert length(result.findings) == 1
      assert hd(result.findings).type == :credit_card
      assert result.action == :block
    end

    test "detects SSN" do
      text = "SSN: 123-45-6789"
      {:ok, result} = PIIDetector.scan(text)

      assert length(result.findings) == 1
      assert hd(result.findings).type == :ssn
      assert result.action == :block
    end

    test "detects email addresses" do
      text = "Contact: john.doe@example.com"
      {:ok, result} = PIIDetector.scan(text)

      assert length(result.findings) == 1
      assert hd(result.findings).type == :email
      assert hd(result.findings).action == :mask
      assert result.action == :allow
    end

    test "returns allow when only masked PII found" do
      text = "Email: test@example.com, Phone: 555-123-4567"
      {:ok, result} = PIIDetector.scan(text)

      assert length(result.findings) == 2
      assert result.action == :allow
    end

    test "blocks when credit card detected" do
      text = "Card: 4532 1234 5678 9012"
      {:ok, result} = PIIDetector.scan(text)

      assert result.action == :block
    end

    test "returns empty findings for clean text" do
      text = "Hello, this is a normal message about software development."
      {:ok, result} = PIIDetector.scan(text)

      assert result.findings == []
      assert result.action == :allow
    end

    test "supports action override" do
      text = "Email: test@example.com"
      {:ok, result} = PIIDetector.scan(text, action_override: :block)

      assert result.action == :block
    end
  end

  describe "blocked?/2" do
    test "returns true when blocked PII found" do
      assert PIIDetector.blocked?("CC: 4532-1234-5678-9012")
    end

    test "returns false when no blocking PII" do
      refute PIIDetector.blocked?("Just a regular message")
    end
  end

  describe "mask_pii/2" do
    test "masks credit card numbers" do
      text = "Card: 4532-1234-5678-9012"
      masked = PIIDetector.mask_pii(text)

      assert masked == "Card: [CREDIT_CARD]"
    end

    test "masks email addresses" do
      text = "Contact: john@example.com"
      masked = PIIDetector.mask_pii(text)

      assert masked == "Contact: [EMAIL]"
    end

    test "masks multiple PII types" do
      text = "Card: 4532-1234-5678-9012, Email: test@example.com"
      masked = PIIDetector.mask_pii(text)

      assert masked == "Card: [CREDIT_CARD], Email: [EMAIL]"
    end
  end

  describe "supported_types/0" do
    test "returns list of supported types" do
      types = PIIDetector.supported_types()

      assert :credit_card in types
      assert :ssn in types
      assert :email in types
      assert :phone in types
    end
  end
end
