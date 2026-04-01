defmodule ControlKeel.Budget.CostOptimizer do
  @moduledoc false

  alias ControlKeel.Budget.Pricing

  def suggest(_session_id, opts \\ []) do
    spending = Keyword.get(opts, :spending, [])
    top_provider = Keyword.get(opts, :top_provider)
    top_model = Keyword.get(opts, :top_model)

    suggestions =
      []
      |> add_model_alternatives(top_provider, top_model)
      |> add_caching_suggestions(spending)
      |> add_local_model_suggestion(spending)
      |> add_batching_suggestion(spending)

    {:ok, suggestions}
  end

  def compare_agents(task_description, opts \\ []) do
    agents = Keyword.get(opts, :agents, default_agents())
    estimated_tokens = Keyword.get(opts, :estimated_tokens, 10_000)

    comparisons =
      Enum.map(agents, fn {agent, provider, model} ->
        case Pricing.estimate_cost_cents(provider, model, %{
               input_tokens: estimated_tokens,
               output_tokens: div(estimated_tokens, 3)
             }) do
          {:ok, cost_cents} ->
            %{
              agent: agent,
              provider: provider,
              model: model,
              estimated_cost_cents: cost_cents,
              estimated_cost_usd: cost_cents / 100,
              input_tokens: estimated_tokens,
              output_tokens: div(estimated_tokens, 3)
            }

          {:error, :unknown_model} ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.estimated_cost_cents)

    cheapest = List.first(comparisons)
    most_expensive = List.last(comparisons)

    {:ok,
     %{
       task_description: task_description,
       estimated_tokens: estimated_tokens,
       comparisons: comparisons,
       cheapest: cheapest,
       most_expensive: most_expensive,
       savings_range:
         cond do
           is_nil(cheapest) or is_nil(most_expensive) -> 0
           true -> most_expensive.estimated_cost_cents - cheapest.estimated_cost_cents
         end
     }}
  end

  defp add_model_alternatives(suggestions, nil, _model), do: suggestions
  defp add_model_alternatives(suggestions, _provider, nil), do: suggestions

  defp add_model_alternatives(suggestions, provider, model) do
    case Pricing.estimate_cost_cents(provider, model, %{
           input_tokens: 100_000,
           output_tokens: 33_000
         }) do
      {:ok, current_cost} ->
        cheaper =
          find_cheaper_alternatives(provider, model, current_cost)

        case cheaper do
          [] ->
            suggestions

          alternatives ->
            best = List.first(alternatives)

            [
              %{
                type: :model_switch,
                priority: :high,
                title: "Switch to a cheaper model",
                description:
                  "Your current model (#{model}) costs ~$#{current_cost / 100}/100k tokens. #{best.model} costs ~$#{best.cost_cents / 100}/100k tokens.",
                savings_percent: round((1 - best.cost_cents / current_cost) * 100),
                current: %{
                  provider: provider,
                  model: model,
                  cost_per_100k_tokens_cents: current_cost
                },
                alternatives: alternatives
              }
              | suggestions
            ]
        end

      {:error, _} ->
        suggestions
    end
  end

  defp add_caching_suggestions(suggestions, spending) do
    total_calls = Enum.count(spending)

    if total_calls > 20 do
      repeat_rate = estimate_repeat_rate(spending)

      if repeat_rate > 0.3 do
        [
          %{
            type: :caching,
            priority: :medium,
            title: "Enable prompt caching",
            description:
              "~#{round(repeat_rate * 100)}% of your requests appear to repeat similar prompts. Enable prompt caching to save on input token costs. Cached input tokens cost 90% less on most providers.",
            savings_percent: round(repeat_rate * 90),
            repeat_rate: repeat_rate
          }
          | suggestions
        ]
      else
        suggestions
      end
    else
      suggestions
    end
  end

  defp add_local_model_suggestion(suggestions, spending) do
    monthly_cost_cents =
      spending
      |> Enum.map(fn s -> Map.get(s, "estimated_cost_cents", 0) end)
      |> Enum.sum()

    if monthly_cost_cents > 50_000 do
      [
        %{
          type: :local_model,
          priority: :low,
          title: "Consider local models for simple tasks",
          description:
            "You're spending $#{monthly_cost_cents / 100}/month on API calls. Running open-source models locally (like Llama 3.3 70B or DeepSeek Coder) costs $0 for simple tasks. Best for code review, formatting, and routine tasks.",
          savings_percent: 60,
          current_monthly_cents: monthly_cost_cents
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp add_batching_suggestion(suggestions, spending) do
    small_calls =
      spending
      |> Enum.filter(fn s ->
        Map.get(s, "input_tokens", 0) + Map.get(s, "output_tokens", 0) < 500
      end)

    if length(small_calls) > 10 do
      [
        %{
          type: :batching,
          priority: :low,
          title: "Batch small requests",
          description:
            "You have #{length(small_calls)} small API calls that could be combined into fewer, larger requests. Each API call has fixed overhead; batching reduces per-request costs.",
          savings_percent: 20,
          small_call_count: length(small_calls)
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp find_cheaper_alternatives(provider, model, current_cost) do
    Pricing.supported_models()
    |> Enum.reject(fn m ->
      m["provider"] == provider and m["model"] == model
    end)
    |> Enum.map(fn m ->
      output_cost = Map.get(m["pricing"], :output, 0)
      %{provider: m["provider"], model: m["model"], cost_cents: output_cost}
    end)
    |> Enum.filter(fn alt -> alt.cost_cents < current_cost and alt.cost_cents > 0 end)
    |> Enum.sort_by(& &1.cost_cents)
    |> Enum.take(3)
  end

  defp estimate_repeat_rate(spending) do
    tools =
      spending
      |> Enum.map(fn s ->
        Map.get(s, "tool", Map.get(s, "metadata", %{}) |> Map.get("tool", "unknown"))
      end)
      |> Enum.frequencies()

    total = Enum.count(spending)

    if total > 0 do
      repeats =
        tools
        |> Enum.count(fn {_tool, count} -> count > 3 end)

      repeats / max(map_size(tools), 1) * 0.5
    else
      0.0
    end
  end

  defp default_agents do
    [
      {"Claude Code", "anthropic", "claude-sonnet-4.6"},
      {"Codex CLI", "openai", "gpt-5.4"},
      {"Gemini CLI", "google", "gemini-2.5-pro"},
      {"DeepSeek", "deepseek", "deepseek-v3"},
      {"Grok", "xai", "grok-3"},
      {"Local Llama", "local", "llama-3.3-70b"}
    ]
  end
end
