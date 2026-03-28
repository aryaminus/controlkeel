defmodule ControlKeel.Skills.Renderer do
  @moduledoc false

  alias ControlKeel.Skills.SkillDefinition
  alias ControlKeel.Skills.TargetFamily

  def render(%SkillDefinition{} = skill, opts \\ []) do
    requested_target = Keyword.get(opts, :target)
    family = TargetFamily.family_for(requested_target)
    metadata = metadata_for_target(skill, requested_target)
    body = render_body(skill, metadata, family)

    %{
      target: requested_target,
      target_family: family,
      metadata: metadata,
      content: body
    }
  end

  def metadata_for_target(%SkillDefinition{} = skill, nil) do
    Enum.find_value(TargetFamily.render_order(), %{}, fn family ->
      Map.get(skill.agent_metadata || %{}, family)
    end) || %{}
  end

  def metadata_for_target(%SkillDefinition{} = skill, target) do
    family = TargetFamily.family_for(target)
    Map.get(skill.agent_metadata || %{}, family || "", %{})
  end

  defp render_body(skill, metadata, family) do
    intro =
      case family do
        nil ->
          nil

        family ->
          """
          Agent target family: #{family}
          Use target-specific behavior when it appears below; otherwise follow the generic skill body.
          """
      end

    frontmatter =
      metadata
      |> Map.get("frontmatter", %{})
      |> normalize_frontmatter()
      |> case do
        %{} = map when map_size(map) > 0 -> yaml_frontmatter(map)
        _ -> nil
      end

    sections =
      [
        frontmatter,
        intro,
        metadata["instructions_prefix"],
        skill.body,
        metadata["instructions_suffix"]
      ]
      |> Enum.reject(&is_nil_or_blank/1)

    Enum.join(sections, "\n\n")
  end

  defp normalize_frontmatter(value) when is_map(value), do: value
  defp normalize_frontmatter(_value), do: %{}

  defp yaml_frontmatter(map) do
    encoded =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map_join("\n", fn {key, value} ->
        "#{key}: #{yaml_value(value)}"
      end)

    "---\n#{encoded}\n---"
  end

  defp yaml_value(value) when is_binary(value), do: Jason.encode!(value)
  defp yaml_value(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp yaml_value(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp yaml_value(value) when is_list(value), do: Jason.encode!(value)
  defp yaml_value(value) when is_map(value), do: Jason.encode!(value)
  defp yaml_value(nil), do: "null"

  defp is_nil_or_blank(nil), do: true
  defp is_nil_or_blank(value), do: String.trim(to_string(value)) == ""
end
