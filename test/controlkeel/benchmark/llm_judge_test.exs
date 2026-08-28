defmodule ControlKeel.Benchmark.LlmJudgeTest do
  use ControlKeel.DataCase, async: true

  alias ControlKeel.Benchmark.LlmJudge

  defp scenario(attrs \\ %{}) do
    Map.merge(
      %{
        content: "Review this config for a public storage bucket exposure.",
        expected_rules: [],
        expected_decision: nil,
        metadata: %{"eval_mode" => "llm_judge", "failure_dimension" => "permission"}
      },
      attrs
    )
  end

  describe "judge_decides?/1" do
    test "true when no deterministic signal" do
      assert LlmJudge.judge_decides?(scenario())
    end

    test "false when expected_rules exist (deterministic stays authoritative)" do
      refute LlmJudge.judge_decides?(scenario(%{expected_rules: ["security.public_bucket"]}))
    end

    test "false when expected_decision is set" do
      refute LlmJudge.judge_decides?(scenario(%{expected_decision: "block"}))
    end
  end

  describe "judge/2 with injectable judge_fn" do
    test "returns parsed verdict from judge_fn" do
      judge_fn = fn _input ->
        {:ok, %{verdict: "pass", score: 92, rationale: "Subject flagged the exposure."}}
      end

      assert {:ok, verdict} =
               LlmJudge.judge(scenario(), %{"decision" => "block"}, judge_fn: judge_fn)

      assert verdict.verdict == "pass"
      assert verdict.score == 92
    end

    test "judgment input carries subject outcome and expectations" do
      test_pid = self()

      judge_fn = fn input ->
        send(test_pid, input)
        {:ok, %{verdict: "unclear", score: 0, rationale: ""}}
      end

      outcome = %{
        "decision" => "block",
        "payload" => %{
          "findings" => [
            %{
              "rule_id" => "security.public_bucket",
              "severity" => "high",
              "plain_message" => "Public bucket"
            }
          ]
        }
      }

      LlmJudge.judge(scenario(), outcome, judge_fn: judge_fn)

      receive do
        input ->
          assert input["subject_decision"] == "block"
          assert input["expected_rules"] == []
          assert [%{"rule_id" => "security.public_bucket"}] = input["subject_findings"]
          assert input["failure_dimension"] == "permission"
      after
        1_000 -> flunk("judge_fn was not invoked")
      end
    end
  end

  describe "parse_verdict robustness (via judge_fn contract)" do
    test "error from judge_fn propagates" do
      judge_fn = fn _input -> {:error, :no_provider} end
      assert {:error, :no_provider} = LlmJudge.judge(scenario(), %{}, judge_fn: judge_fn)
    end
  end
end
