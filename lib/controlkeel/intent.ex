defmodule ControlKeel.Intent do
  @moduledoc false

  alias ControlKeel.Intent.{BoundarySummary, Domains, ExecutionBrief, ExecutionPosture, Router}

  def compile(attrs, opts \\ []) when is_map(attrs) do
    Router.compile(normalize_attrs(attrs), opts)
  end

  def occupation_profiles, do: Domains.occupation_profiles()
  def agent_options, do: Domains.agent_options()
  def supported_packs, do: Domains.supported_packs()
  def pack_label(domain_pack), do: Domains.pack_label(domain_pack)
  def interview_questions(occupation_id), do: Domains.questions_for_occupation(occupation_id)
  def preflight_context(attrs), do: Domains.preflight_context(attrs)
  def provider_options, do: Router.provider_options()

  def to_brief_map(%ExecutionBrief{} = brief), do: ExecutionBrief.to_map(brief)
  def boundary_summary(brief_or_map), do: BoundarySummary.build(brief_or_map)
  def execution_posture(brief_or_map), do: ExecutionPosture.build(brief_or_map)

  defp normalize_attrs(attrs) do
    attrs
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
    |> Map.update("interview_answers", %{}, fn answers ->
      answers
      |> Enum.into(%{}, fn {key, value} ->
        {to_string(key), to_string(value || "") |> String.trim()}
      end)
    end)
  end
end
