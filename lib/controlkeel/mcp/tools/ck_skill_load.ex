defmodule ControlKeel.MCP.Tools.CkSkillLoad do
  @moduledoc """
  MCP tool: ck_skill_load

  Loads the full instructions for a named AgentSkill, returning
  the SKILL.md body wrapped in <skill_content> tags per the
  AgentSkills specification (https://agentskills.io/specification).

  Agents call this after ck_skill_list to activate a skill and
  receive detailed instructions, scripts, and resource references.
  """

  alias ControlKeel.Skills.Activation
  alias ControlKeel.Skills.Registry

  def call(%{"name" => name} = arguments) do
    project_root = Map.get(arguments, "project_root")
    session_id = Map.get(arguments, "session_id")

    case Registry.get(name, project_root) do
      nil ->
        {:error,
         {:invalid_arguments,
          "Skill '#{name}' not found. Call ck_skill_list to see available skills."}}

      skill ->
        activation = Activation.mark_loaded(skill.name, project_root, session_id)

        resources_block =
          if skill.resources == [] do
            ""
          else
            entries = Enum.map(skill.resources, fn r -> "  <file>#{r}</file>" end)
            "\n<skill_resources>\n#{Enum.join(entries, "\n")}\n</skill_resources>"
          end

        content =
          "<skill_content name=\"#{skill.name}\">\n" <>
            "Skill directory: #{skill.skill_dir}\n" <>
            "Relative paths in this skill are relative to the skill directory.\n\n" <>
            "#{skill.body}#{resources_block}\n</skill_content>"

        {:ok,
         %{
           "name" => skill.name,
           "description" => skill.description,
           "scope" => skill.scope,
           "allowed_tools" => skill.allowed_tools,
           "required_mcp_tools" => skill.required_mcp_tools,
           "compatibility" => skill.compatibility,
           "compatibility_targets" => skill.compatibility_targets,
           "source" => skill.source,
           "activation" => to_string(activation),
           "diagnostics" => Enum.map(skill.diagnostics, &diagnostic_summary/1),
           "content" => content,
           "resources" => skill.resources
         }}
    end
  end

  def call(_arguments) do
    {:error, {:invalid_arguments, "name is required"}}
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
end
