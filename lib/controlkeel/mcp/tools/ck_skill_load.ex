defmodule ControlKeel.MCP.Tools.CkSkillLoad do
  @moduledoc """
  MCP tool: ck_skill_load

  Loads the full instructions for a named AgentSkill, returning
  the SKILL.md body wrapped in <skill_content> tags per the
  AgentSkills specification (https://agentskills.io/specification).

  Agents call this after ck_skill_list to activate a skill and
  receive detailed instructions, scripts, and resource references.
  """

  alias ControlKeel.Skills.Registry

  def call(%{"name" => name} = arguments) do
    project_root = Map.get(arguments, "project_root")

    case Registry.get(name, project_root) do
      nil ->
        {:error,
         {:invalid_arguments,
          "Skill '#{name}' not found. Call ck_skill_list to see available skills."}}

      skill ->
        resources = discover_resources(skill.path)

        resources_block =
          if resources == [] do
            ""
          else
            entries = Enum.map(resources, fn r -> "  <file>#{r}</file>" end)
            "\n<skill_resources>\n#{Enum.join(entries, "\n")}\n</skill_resources>"
          end

        content =
          "<skill_content name=\"#{skill.name}\">\n#{skill.body}#{resources_block}\n</skill_content>"

        {:ok,
         %{
           "name" => skill.name,
           "description" => skill.description,
           "scope" => skill.scope,
           "allowed_tools" => skill.allowed_tools,
           "compatibility" => skill.compatibility,
           "content" => content,
           "resources" => resources
         }}
    end
  end

  def call(_arguments) do
    {:error, {:invalid_arguments, "name is required"}}
  end

  # List scripts/, references/, and assets/ files relative to the skill dir
  defp discover_resources(skill_path) do
    skill_dir = Path.dirname(skill_path)
    resource_dirs = ["scripts", "references", "assets"]

    Enum.flat_map(resource_dirs, fn sub ->
      sub_path = Path.join(skill_dir, sub)

      case File.ls(sub_path) do
        {:ok, files} ->
          files
          |> Enum.reject(&String.starts_with?(&1, "."))
          |> Enum.map(&Path.join(sub, &1))

        _ ->
          []
      end
    end)
  end
end
