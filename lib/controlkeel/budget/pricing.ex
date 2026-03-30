defmodule ControlKeel.Budget.Pricing do
  @moduledoc false

  @models %{
    {"anthropic", "claude-sonnet-4.6"} => %{input: 300, cached_input: 30, output: 1500},
    {"anthropic", "claude-sonnet-4.5"} => %{input: 300, cached_input: 30, output: 1500},
    {"anthropic", "claude-opus-4.6"} => %{input: 500, cached_input: 50, output: 2500},
    {"anthropic", "claude-opus-4.5"} => %{input: 500, cached_input: 50, output: 2500},
    {"anthropic", "claude-haiku-4.5"} => %{input: 100, cached_input: 10, output: 500},
    {"openai", "gpt-5.4"} => %{input: 250, cached_input: 25, output: 1500},
    {"openai", "gpt-5.4-mini"} => %{input: 75, cached_input: 8, output: 450},
    {"openai", "gpt-5.4-nano"} => %{input: 20, cached_input: 2, output: 125},
    {"openai", "o3"} => %{input: 200, cached_input: 10, output: 800},
    {"openai", "o4-mini"} => %{input: 110, cached_input: 8, output: 440},
    {"google", "gemini-2.5-pro"} => %{input: 125, cached_input: 13, output: 500},
    {"google", "gemini-2.5-flash"} => %{input: 15, cached_input: 2, output: 60},
    {"google", "gemini-2.0-flash"} => %{input: 10, cached_input: 1, output: 40},
    {"deepseek", "deepseek-r1"} => %{input: 55, cached_input: 14, output: 219},
    {"deepseek", "deepseek-v3"} => %{input: 27, cached_input: 7, output: 110},
    {"groq", "llama-4-maverick"} => %{input: 20, cached_input: 5, output: 60},
    {"groq", "llama-3.3-70b"} => %{input: 59, cached_input: 15, output: 79},
    {"together", "llama-4-maverick"} => %{input: 22, cached_input: 6, output: 88},
    {"together", "deepseek-r1"} => %{input: 55, cached_input: 14, output: 219},
    {"cohere", "command-r-plus"} => %{input: 250, cached_input: 25, output: 1000},
    {"cohere", "command-r"} => %{input: 50, cached_input: 5, output: 250},
    {"xai", "grok-3"} => %{input: 300, cached_input: 30, output: 1500},
    {"xai", "grok-3-mini"} => %{input: 30, cached_input: 3, output: 150},
    {"mistral", "mistral-large"} => %{input: 200, cached_input: 20, output: 600},
    {"mistral", "mistral-medium"} => %{input: 40, cached_input: 4, output: 120},
    {"local", "llama-3.3-70b"} => %{input: 0, cached_input: 0, output: 0},
    {"local", "codestral"} => %{input: 0, cached_input: 0, output: 0},
    {"local", "deepseek-coder-v2"} => %{input: 0, cached_input: 0, output: 0}
  }

  @aliases %{
    {"anthropic", "claude sonnet 4.6"} => {"anthropic", "claude-sonnet-4.6"},
    {"anthropic", "claude sonnet 4.5"} => {"anthropic", "claude-sonnet-4.5"},
    {"anthropic", "claude opus 4.6"} => {"anthropic", "claude-opus-4.6"},
    {"anthropic", "claude opus 4.5"} => {"anthropic", "claude-opus-4.5"},
    {"anthropic", "claude haiku 4.5"} => {"anthropic", "claude-haiku-4.5"},
    {"openai", "gpt-5.4 mini"} => {"openai", "gpt-5.4-mini"},
    {"openai", "gpt-5.4 nano"} => {"openai", "gpt-5.4-nano"},
    {"google", "gemini 2.5 pro"} => {"google", "gemini-2.5-pro"},
    {"google", "gemini 2.5 flash"} => {"google", "gemini-2.5-flash"},
    {"google", "gemini 2.0 flash"} => {"google", "gemini-2.0-flash"},
    {"deepseek", "r1"} => {"deepseek", "deepseek-r1"},
    {"deepseek", "v3"} => {"deepseek", "deepseek-v3"},
    {"groq", "llama 4 maverick"} => {"groq", "llama-4-maverick"},
    {"groq", "llama 3.3 70b"} => {"groq", "llama-3.3-70b"},
    {"xai", "grok 3"} => {"xai", "grok-3"},
    {"xai", "grok 3 mini"} => {"xai", "grok-3-mini"},
    {"mistral", "large"} => {"mistral", "mistral-large"},
    {"mistral", "medium"} => {"mistral", "mistral-medium"},
    {"cohere", "command r plus"} => {"cohere", "command-r-plus"},
    {"cohere", "command r"} => {"cohere", "command-r"}
  }

  def estimate_cost_cents(provider, model, counts) when is_map(counts) do
    case fetch_model(provider, model) do
      {:ok, pricing} ->
        input_tokens = Map.get(counts, :input_tokens, 0) || 0
        cached_input_tokens = Map.get(counts, :cached_input_tokens, 0) || 0
        output_tokens = Map.get(counts, :output_tokens, 0) || 0

        total_cents =
          per_million_cost(input_tokens, pricing.input) +
            per_million_cost(cached_input_tokens, pricing.cached_input) +
            per_million_cost(output_tokens, pricing.output)

        {:ok, total_cents}

      {:error, :unknown_model} ->
        {:error, :unknown_model}
    end
  end

  def supported_models do
    Enum.map(@models, fn {{provider, model}, pricing} ->
      %{"provider" => provider, "model" => model, "pricing" => pricing}
    end)
  end

  def fallback_estimate_cents(counts) when is_map(counts) do
    max_input =
      Enum.max_by(@models, fn {_key, pricing} -> pricing.input end)
      |> elem(1)
      |> Map.fetch!(:input)

    max_cached =
      Enum.max_by(@models, fn {_key, pricing} -> pricing.cached_input end)
      |> elem(1)
      |> Map.fetch!(:cached_input)

    max_output =
      Enum.max_by(@models, fn {_key, pricing} -> pricing.output end)
      |> elem(1)
      |> Map.fetch!(:output)

    input_tokens = Map.get(counts, :input_tokens, 0) || 0
    cached_input_tokens = Map.get(counts, :cached_input_tokens, 0) || 0
    output_tokens = Map.get(counts, :output_tokens, 0) || 0

    per_million_cost(input_tokens, max_input) +
      per_million_cost(cached_input_tokens, max_cached) +
      per_million_cost(output_tokens, max_output)
  end

  defp fetch_model(provider, model) do
    provider = normalize(provider)
    model = normalize(model)

    key =
      case Map.get(@aliases, {provider, model}) do
        nil -> {provider, model}
        resolved -> resolved
      end

    case Map.fetch(@models, key) do
      {:ok, pricing} -> {:ok, pricing}
      :error -> {:error, :unknown_model}
    end
  end

  defp per_million_cost(0, _rate), do: 0

  defp per_million_cost(tokens, rate_cents_per_million) do
    Float.ceil(tokens * rate_cents_per_million / 1_000_000)
    |> trunc()
  end

  defp normalize(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end
end
