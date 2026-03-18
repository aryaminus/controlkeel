defmodule ControlKeel.Intent.Router do
  @moduledoc false

  alias ControlKeel.Intent
  alias ControlKeel.Intent.{Domains, ExecutionBrief, Prompt}
  alias ControlKeel.Intent.Providers.{Anthropic, Ollama, OpenAI, OpenRouter}

  @providers %{
    anthropic: Anthropic,
    openai: OpenAI,
    openrouter: OpenRouter,
    ollama: Ollama
  }

  def compile(attrs, opts \\ []) do
    prompt = Prompt.build(attrs)
    providers = ordered_providers(attrs, opts)
    fallback_chain = Enum.map(providers, &Atom.to_string/1)

    try_providers(providers, prompt, attrs, fallback_chain, opts)
  end

  def provider_options do
    Enum.map(@providers, fn {provider, _module} -> Atom.to_string(provider) end)
  end

  def provider_module(provider), do: Map.fetch!(@providers, provider)

  def ordered_providers(attrs, opts) do
    preflight = Domains.preflight_context(attrs)

    default_order =
      case preflight.preliminary_risk_tier do
        tier when tier in ["high", "critical"] -> [:anthropic, :openai, :openrouter, :ollama]
        _moderate -> [:openai, :anthropic, :openrouter, :ollama]
      end

    requested =
      Keyword.get(opts, :providers) ||
        default_provider_override() ||
        default_order

    requested
    |> List.wrap()
    |> Enum.map(&normalize_provider/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> then(fn providers ->
      providers ++ Enum.reject(default_order, &(&1 in providers))
    end)
  end

  defp try_providers([], _prompt, _attrs, _fallback_chain, _opts) do
    emit_compiler_failure(:none, :no_provider_succeeded)
    {:error, :no_provider_succeeded}
  end

  defp try_providers([provider | rest], prompt, attrs, fallback_chain, opts) do
    module = provider_module(provider)
    attempt_opts = Keyword.put(opts, :provider, provider)

    case attempt_provider(module, prompt, attempt_opts) do
      {:ok, brief_map, provider_metadata} ->
        compiler_metadata = %{
          "provider" => Atom.to_string(provider),
          "model" => provider_metadata["model"],
          "schema_version" => ExecutionBrief.schema_version(),
          "fallback_chain" => fallback_chain,
          "interview_answers" => Map.get(attrs, "interview_answers", %{}),
          "occupation" => Map.get(attrs, "occupation"),
          "domain_pack" => prompt.context.domain_pack
        }

        case ExecutionBrief.from_provider_response(brief_map, compiler_metadata) do
          {:ok, brief} ->
            emit_compiler_success(provider, compiler_metadata["model"], fallback_chain)
            {:ok, brief}

          {:error, _changeset} ->
            if Keyword.get(opts, :validated_retry_provider) == provider do
              emit_fallback(provider, List.first(rest), :invalid_structured_output)

              if rest == [] and dev_fallback?(opts) do
                heuristic_brief(attrs, compiler_metadata, fallback_chain)
              else
                try_providers(rest, prompt, attrs, fallback_chain, opts)
              end
            else
              emit_fallback(provider, provider, :invalid_structured_output_retry)

              try_providers(
                [provider | rest],
                prompt,
                attrs,
                fallback_chain,
                Keyword.put(opts, :validated_retry_provider, provider)
              )
            end
        end

      {:skip, reason} ->
        emit_fallback(provider, List.first(rest), reason)

        if rest == [] and dev_fallback?(opts) do
          heuristic_brief(attrs, %{"model" => "heuristic"}, fallback_chain)
        else
          try_providers(rest, prompt, attrs, fallback_chain, opts)
        end

      {:error, reason} ->
        emit_fallback(provider, List.first(rest), reason)

        if rest == [] and dev_fallback?(opts) do
          heuristic_brief(attrs, %{"model" => "heuristic"}, fallback_chain)
        else
          try_providers(rest, prompt, attrs, fallback_chain, opts)
        end
    end
  end

  defp attempt_provider(module, prompt, opts) do
    case module.compile(prompt, opts) do
      {:error, :invalid_response} ->
        module.compile(prompt, Keyword.put(opts, :retry, true))

      other ->
        other
    end
  end

  defp heuristic_brief(attrs, provider_metadata, fallback_chain) do
    plan = ControlKeel.Mission.Planner.build(attrs)
    preflight = Domains.preflight_context(attrs)
    answers = Map.get(attrs, "interview_answers", %{})

    users =
      present_value(Map.get(attrs, "users")) || present_value(answers["who_uses_it"]) ||
        "project operators"

    data_summary =
      present_value(Map.get(attrs, "data")) ||
        present_value(answers["data_involved"]) ||
        "Repo code and configuration"

    key_features =
      answers["first_release"]
      |> split_list()
      |> case do
        [] -> plan.session.execution_brief.key_features || []
        values -> values
      end

    objective =
      plan.session.execution_brief.objective ||
        "Stand up the first production-safe version of the requested workflow."

    next_step =
      plan.session.execution_brief.next_step ||
        "Generate the smallest useful first slice and validate it before release."

    launch_window =
      plan.session.execution_brief.launch_window ||
        "Launch after one controlled internal pass."

    compiler_metadata = %{
      "provider" => "heuristic",
      "model" => provider_metadata["model"] || "heuristic",
      "schema_version" => ExecutionBrief.schema_version(),
      "fallback_chain" => fallback_chain,
      "interview_answers" => answers,
      "occupation" => Map.get(attrs, "occupation"),
      "domain_pack" => Domains.preflight_context(attrs).domain_pack
    }

    brief_map = %{
      "project_name" => Map.get(attrs, "project_name"),
      "idea" => Map.get(attrs, "idea"),
      "objective" => objective,
      "users" => users,
      "occupation" => preflight.occupation.label,
      "domain_pack" => compiler_metadata["domain_pack"],
      "risk_tier" => preflight.preliminary_risk_tier,
      "data_summary" => data_summary,
      "compliance" => preflight.compliance,
      "recommended_stack" => preflight.stack_guidance,
      "acceptance_criteria" => acceptance_from_features(key_features),
      "open_questions" => open_questions_from(attrs, answers),
      "estimated_tasks" => max(length(key_features) + 2, 3),
      "budget_note" =>
        present_value(answers["constraints"]) || plan.session.execution_brief.budget_note,
      "next_step" => next_step,
      "launch_window" => launch_window,
      "success_signal" =>
        "The first users complete the core workflow with the expected review gates.",
      "key_features" => key_features
    }

    case ExecutionBrief.from_provider_response(brief_map, compiler_metadata) do
      {:ok, brief} ->
        emit_compiler_success(:heuristic, compiler_metadata["model"], fallback_chain)
        {:ok, brief}

      {:error, changeset} ->
        emit_compiler_failure(:heuristic, changeset)
        {:error, changeset}
    end
  end

  defp acceptance_from_features(features) do
    features
    |> List.wrap()
    |> Enum.map(&"The first release supports #{String.downcase(&1)} without manual patching.")
    |> case do
      [] -> ["The first release completes one governed workflow end to end."]
      values -> values
    end
  end

  defp normalize_provider(provider) when is_atom(provider) do
    if Map.has_key?(@providers, provider), do: provider, else: nil
  end

  defp normalize_provider(provider) when is_binary(provider) do
    provider
    |> String.trim()
    |> String.downcase()
    |> case do
      "anthropic" -> :anthropic
      "openai" -> :openai
      "openrouter" -> :openrouter
      "ollama" -> :ollama
      _unknown -> nil
    end
  end

  defp default_provider_override do
    case Application.get_env(:controlkeel, Intent, [])[:default_provider] do
      nil -> nil
      provider -> [provider]
    end
  end

  defp dev_fallback?(opts) do
    case Keyword.get(opts, :allow_dev_fallback, :unset) do
      :unset ->
        Application.get_env(:controlkeel, Intent, [])[:dev_fallback] || test_env?()

      value ->
        value
    end
  end

  defp test_env? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  end

  defp open_questions_from(attrs, answers) do
    questions =
      []
      |> maybe_append_question(
        blank?(Map.get(attrs, "project_name")),
        "What should this mission be called in the product and repo?"
      )
      |> maybe_append_question(
        blank?(answers["constraints"]),
        "What hosting, budget, or approval limits should constrain the first release?"
      )

    case questions do
      [] -> ["Which external system or approval checkpoint should be clarified before launch?"]
      values -> values
    end
  end

  defp maybe_append_question(list, true, question), do: list ++ [question]
  defp maybe_append_question(list, false, _question), do: list

  defp split_list(nil), do: []

  defp split_list(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_list(value) when is_list(value), do: Enum.map(value, &to_string/1)
  defp split_list(_value), do: []

  defp present_value(value) do
    value = to_string(value || "") |> String.trim()
    if value == "", do: nil, else: value
  end

  defp blank?(value), do: present_value(value) == nil

  defp emit_fallback(provider, next_provider, reason) do
    :telemetry.execute(
      [:controlkeel, :intent, :compiler, :fallback],
      %{count: 1},
      %{
        provider: Atom.to_string(provider),
        next_provider: if(next_provider, do: Atom.to_string(next_provider), else: nil),
        reason: inspect(reason)
      }
    )
  end

  defp emit_compiler_success(provider, model, fallback_chain) do
    :telemetry.execute(
      [:controlkeel, :intent, :compiler, :success],
      %{count: 1},
      %{provider: to_string(provider), model: model, fallback_chain: fallback_chain}
    )
  end

  defp emit_compiler_failure(provider, reason) do
    :telemetry.execute(
      [:controlkeel, :intent, :compiler, :failure],
      %{count: 1},
      %{provider: if(provider, do: to_string(provider), else: nil), reason: inspect(reason)}
    )
  end
end
