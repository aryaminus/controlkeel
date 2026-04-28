defmodule ControlKeel.MCP.Tools.CkSkillList do
  @moduledoc """
  MCP tool: ck_skill_list

  Returns the available AgentSkills catalog for the current project.
  Agents should call this first to discover capabilities, then call
  ck_skill_load to activate a specific skill.
  """

  alias ControlKeel.Skills.Registry
  alias ControlKeel.Skills.TargetFamily
  alias ControlKeel.Skills.TargetResolver

  def call(arguments) do
    project_root = Map.get(arguments, "project_root")
    format = Map.get(arguments, "format", "json")
    target = TargetResolver.resolve(project_root, Map.get(arguments, "target"))
    target_family = TargetResolver.family(project_root, target)
    analysis = Registry.analyze(project_root)

    skills =
      Enum.filter(analysis.skills, fn skill ->
        compatible_target?(skill.compatibility_targets || [], target, target_family)
      end)

    entries =
      Enum.map(skills, fn s ->
        %{
          "name" => s.name,
          "description" => s.description,
          "scope" => s.scope,
          "allowed_tools" => s.allowed_tools,
          "required_mcp_tools" => s.required_mcp_tools,
          "license" => s.license,
          "compatibility" => s.compatibility,
          "compatibility_targets" => s.compatibility_targets,
          "path" => s.path,
          "source" => s.source,
          "owner" => s.owner,
          "content_hash" => s.content_hash,
          "install_state" => s.install_state,
          "diagnostics" => Enum.map(s.diagnostics, &diagnostic_summary/1)
        }
      end)

    prompt_block = if format == "xml", do: Registry.prompt_block(project_root), else: nil

    result =
      %{
        "skills" => entries,
        "total" => length(entries),
        "target" => target,
        "target_family" => target_family,
        "trusted_project_skills" => analysis.trusted_project?,
        "diagnostics" => Enum.map(analysis.diagnostics, &diagnostic_summary/1),
        "usage_hint" =>
          "Call ck_skill_load with a skill name to load its full instructions into your context."
      }
      |> then(fn r ->
        if prompt_block, do: Map.put(r, "prompt_block", prompt_block), else: r
      end)

    {:ok, result}
  end

  defp diagnostic_summary(diagnostic) do
    %{
      "level" => diagnostic.level,
      "code" => diagnostic.code,
      "message" => diagnostic.message,
      "path" => diagnostic.path,
      "skill_name" => diagnostic.skill_name
    }
  end

  defp compatible_target?(targets, target, target_family) do
    target in targets or
      target_family in targets or
      Enum.any?(targets, fn candidate ->
        TargetFamily.family_for(candidate) == target_family
      end)
  end
end
