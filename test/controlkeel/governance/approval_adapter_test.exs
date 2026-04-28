defmodule ControlKeel.Governance.ApprovalAdapterTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Governance.ApprovalAdapter

  describe "evaluate/2 with t3code agent" do
    test "accepts low-tier tool reads" do
      result = ApprovalAdapter.evaluate("t3code", %{"tool" => "file_read"})

      assert result.decision in [:accept, :accept_for_session]
      refute result.requires_human_approval
    end

    test "blocks critical-tier secrets tool" do
      result = ApprovalAdapter.evaluate("t3code", %{"tool" => "secrets"})

      assert result.decision == :decline
      assert result.requires_human_approval
      assert "CRITICAL_TOOL_GATE" in result.policy_rule_ids
    end

    test "declines for unknown agent" do
      result = ApprovalAdapter.evaluate("nonexistent-agent", %{"tool" => "bash"})

      assert result.decision == :decline
      assert result.requires_human_approval
    end
  end

  describe "evaluate/2 with approval-required mode" do
    test "blocks high-tier shell tool under approval_required" do
      result =
        ApprovalAdapter.evaluate("t3code", %{"tool" => "bash"}, policy_mode: "approval_required")

      assert result.decision == :decline
      assert result.requires_human_approval
    end

    test "allows policy-gated medium-tier tool under approval_required without pestering" do
      result =
        ApprovalAdapter.evaluate("t3code", %{"tool" => "file_edit"},
          policy_mode: "approval_required"
        )

      assert result.decision == :accept_for_session
      refute result.requires_human_approval
      assert "INTERACTIVE_GATE_MEDIUM_POLICY_ALLOW" in result.policy_rule_ids
    end
  end

  describe "evaluate/2 with auto-accept-edits mode" do
    test "allows file edit under auto_accept_edits" do
      result =
        ApprovalAdapter.evaluate("t3code", %{"tool" => "file_edit"},
          policy_mode: "auto_accept_edits"
        )

      # file_edit is medium tier, auto_accept only denies high/critical
      assert result.decision in [:accept, :accept_for_session]
    end

    test "blocks shell under auto_accept_edits" do
      result =
        ApprovalAdapter.evaluate("t3code", %{"tool" => "bash"}, policy_mode: "auto_accept_edits")

      assert result.decision == :decline
      assert result.requires_human_approval
    end
  end

  describe "tool_risk_tier/1" do
    test "classifies shell commands as high risk" do
      assert ApprovalAdapter.tool_risk_tier(%{"tool" => "bash"}) == :high
      assert ApprovalAdapter.tool_risk_tier(%{"tool" => "shell"}) == :high
    end

    test "classifies secrets as critical" do
      assert ApprovalAdapter.tool_risk_tier(%{"tool" => "secrets"}) == :critical
    end

    test "classifies file reads as low" do
      assert ApprovalAdapter.tool_risk_tier(%{"tool" => "file_read"}) == :low
    end

    test "defaults to medium for unknown tools" do
      assert ApprovalAdapter.tool_risk_tier(%{"tool" => "unknown_tool"}) == :medium
    end
  end

  describe "evaluate_batch/3" do
    test "returns per-tool decisions" do
      results =
        ApprovalAdapter.evaluate_batch(
          "t3code",
          [
            %{"tool" => "file_read", "request_id" => "r1"},
            %{"tool" => "bash", "request_id" => "r2"}
          ],
          policy_mode: "approval_required"
        )

      assert length(results) == 2

      {_read_key, read_result} = Enum.find(results, fn {k, _v} -> k == "r1" end)
      assert read_result.decision in [:accept, :accept_for_session]

      {_bash_key, bash_result} = Enum.find(results, fn {k, _v} -> k == "r2" end)
      assert bash_result.decision == :decline
    end
  end
end
