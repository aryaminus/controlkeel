defmodule ControlKeel.Intent.Prompt do
  @moduledoc false

  alias ControlKeel.Intent.Domains

  def build(attrs) do
    context = Domains.preflight_context(attrs)
    occupation = context.occupation
    pack = Domains.pack(context.domain_pack)
    answers = Map.get(attrs, "interview_answers", %{})

    %{
      system: system_prompt(pack, context.preliminary_risk_tier),
      user: user_prompt(attrs, occupation, pack, context.preliminary_risk_tier, answers),
      context: context
    }
  end

  defp system_prompt(pack, preliminary_risk_tier) do
    """
    You are ControlKeel's intent compiler. Your job is to convert ambiguous product requests into a production-minded execution brief for AI-assisted delivery.

    Return only structured data matching the provided schema.

    Constraints:
    - Choose a realistic risk_tier of moderate, high, or critical.
    - Keep the first release narrow and reviewable.
    - Prefer practical stacks and concrete acceptance criteria.
    - Map the solution to the provided domain pack and compliance context.
    - If information is missing, infer conservatively and include open questions.
    - The preliminary risk signal is #{preliminary_risk_tier}; only downgrade it when clearly justified.

    Domain guidance:
    - Compliance expectations: #{Enum.join(pack.compliance, ", ")}
    - Stack guidance: #{pack.stack_guidance}
    - Validation emphasis: #{pack.validation_language}
    """
  end

  defp user_prompt(attrs, occupation, pack, preliminary_risk_tier, answers) do
    """
    Occupation:
    - #{occupation.label}
    - #{occupation.description}

    Domain pack: #{occupation.domain_pack}
    Agent tool: #{Map.get(attrs, "agent")}
    Project name: #{Map.get(attrs, "project_name", "")}
    Core product prompt:
    #{Map.get(attrs, "idea")}

    Guided interview answers:
    #{render_answers(pack.questions, answers)}

    Produce an execution brief for the smallest credible first release.
    Use the domain pack #{occupation.domain_pack}, compliance context #{Enum.join(pack.compliance, ", ")}, and preliminary risk tier #{preliminary_risk_tier}.
    """
  end

  defp render_answers(questions, answers) do
    questions
    |> Enum.map(fn question ->
      "- #{question.label}: #{Map.get(answers, question.id, "")}"
    end)
    |> Enum.join("\n")
  end
end
