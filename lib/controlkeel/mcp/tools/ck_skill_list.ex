defmodule ControlKeel.MCP.Tools.CkSkillList do
  @moduledoc """
  MCP tool: ck_skill_list

  Returns the available AgentSkills catalog for the current project.
  Agents should call this first to discover capabilities, then call
  ck_skill_load to activate a specific skill.
  """

  alias ControlKeel.Skills.Registry

  def call(arguments) do
    project_root = Map.get(arguments, "project_root")
    format = Map.get(arguments, "format", "json")

    skills = Registry.catalog(project_root)

    entries =
      Enum.map(skills, fn s ->
        %{
          "name" => s.name,
          "description" => s.description,
          "scope" => s.scope,
          "allowed_tools" => s.allowed_tools,
          "license" => s.license,
          "compatibility" => s.compatibility,
          "path" => s.path
        }
      end)

    prompt_block = if format == "xml", do: Registry.prompt_block(project_root), else: nil

    result =
      %{
        "skills" => entries,
        "total" => length(entries),
        "usage_hint" =>
          "Call ck_skill_load with a skill name to load its full instructions into your context."
      }
      |> then(fn r ->
        if prompt_block, do: Map.put(r, "prompt_block", prompt_block), else: r
      end)

    {:ok, result}
  end
end
