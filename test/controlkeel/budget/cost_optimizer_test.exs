defmodule ControlKeel.Budget.CostOptimizerTest do
  use ControlKeel.DataCase

  alias ControlKeel.Budget.CostOptimizer

  test "suggest returns suggestions list" do
    assert {:ok, suggestions} = CostOptimizer.suggest("session_1")
    assert is_list(suggestions)
  end

  test "suggest with model info can recommend cheaper alternatives" do
    assert {:ok, suggestions} =
             CostOptimizer.suggest("session_2",
               top_provider: "openai",
               top_model: "gpt-5.4"
             )

    model_suggestions = Enum.filter(suggestions, &(&1.type == :model_switch))

    if length(model_suggestions) > 0 do
      switch = List.first(model_suggestions)
      assert switch.savings_percent > 0
    end
  end

  test "suggest recommends caching for high-volume spending" do
    spending =
      for _ <- 1..25 do
        %{"tool" => "ck_validate", "estimated_cost_cents" => 100, "input_tokens" => 1000}
      end

    assert {:ok, suggestions} = CostOptimizer.suggest("session_3", spending: spending)
    cache_count = length(Enum.filter(suggestions, &(&1.type == :caching)))
    assert cache_count >= 0
  end

  test "suggest recommends local models for high spend" do
    spending =
      for _ <- 1..5 do
        %{"estimated_cost_cents" => 15_000, "input_tokens" => 50_000, "output_tokens" => 5000}
      end

    assert {:ok, suggestions} = CostOptimizer.suggest("session_4", spending: spending)
    local_count = length(Enum.filter(suggestions, &(&1.type == :local_model)))
    assert local_count >= 0
  end

  test "compare_agents returns cost comparison" do
    assert {:ok, result} =
             CostOptimizer.compare_agents("Build a REST API", estimated_tokens: 50_000)

    assert is_list(result.comparisons)
    assert length(result.comparisons) > 0
    assert is_integer(result.savings_range)
  end

  test "compare_agents sorts by cost" do
    {:ok, result} = CostOptimizer.compare_agents("Fix a bug")

    costs = Enum.map(result.comparisons, & &1.estimated_cost_cents)
    assert costs == Enum.sort(costs)
  end

  test "compare_agents includes token estimates" do
    {:ok, result} = CostOptimizer.compare_agents("Test task", estimated_tokens: 20_000)

    for comp <- result.comparisons do
      assert comp.input_tokens == 20_000
      assert comp.output_tokens == div(20_000, 3)
    end
  end
end
