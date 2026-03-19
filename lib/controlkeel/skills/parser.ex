defmodule ControlKeel.Skills.Parser do
  @moduledoc false

  alias ControlKeel.Skills.SkillDefinition
  alias ControlKeel.Skills.SkillDiagnostic
  alias ControlKeel.Skills.SkillTarget

  @name_regex ~r/^[a-z0-9][a-z0-9-]{0,63}$/
  @resource_dirs ~w(scripts references assets agents)

  def parse(skill_path, scope) do
    with {:ok, content} <- File.read(skill_path),
         {:ok, meta, body} <- extract_frontmatter(content) do
      skill_dir = Path.dirname(skill_path)
      parent_name = Path.basename(skill_dir)
      name = Map.get(meta, "name", parent_name)
      description = Map.get(meta, "description", "") |> to_string() |> String.trim()

      diagnostics =
        []
        |> maybe_add_name_mismatch(name, parent_name, skill_path)
        |> maybe_add_name_warning(name, skill_path)
        |> maybe_add_missing_description(description, skill_path, name)

      if description == "" do
        {:error,
         %SkillDiagnostic{
           level: "error",
           code: "missing_description",
           message: "Skill is missing a non-empty description.",
           path: skill_path,
           skill_name: name
         }}
      else
        {openai_metadata, openai_diagnostics} = read_openai_metadata(skill_dir, name)
        resources = discover_resources(skill_dir)

        diagnostics =
          diagnostics
          |> Kernel.++(openai_diagnostics)
          |> Kernel.++(reference_diagnostics(body, skill_dir, skill_path, name))
          |> Kernel.++(compatibility_diagnostics(meta, openai_metadata, skill_path, name))

        allowed_tools = normalize_list(Map.get(meta, "allowed-tools", []))
        required_mcp_tools = normalize_required_tools(meta, allowed_tools)

        compatibility_targets =
          meta
          |> compatibility_targets(openai_metadata)
          |> Enum.uniq()

        {:ok,
         %SkillDefinition{
           name: name,
           description: description,
           path: skill_path,
           skill_dir: skill_dir,
           body: String.trim(body),
           metadata: Map.get(meta, "metadata", %{}),
           scope: scope,
           source: classify_source(skill_path),
           license: normalize_nil(Map.get(meta, "license")),
           compatibility: normalize_compatibility(Map.get(meta, "compatibility")),
           compatibility_targets: compatibility_targets,
           allowed_tools: allowed_tools,
           required_mcp_tools: required_mcp_tools,
           disable_model_invocation:
             truthy?(Map.get(meta, "disable-model-invocation")) ||
               openai_metadata |> get_in(["policy", "allow_implicit_invocation"]) |> falsey?(),
           user_invocable: not falsey?(Map.get(meta, "user-invocable")),
           resources: resources,
           diagnostics: diagnostics,
           openai: openai_metadata,
           install_state: %{}
         }}
      end
    end
  end

  defp extract_frontmatter(content) do
    case Regex.run(~r/\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*\r?\n(.*)\z/s, content,
           capture: :all_but_first
         ) do
      [yaml, body] ->
        case parse_yaml_frontmatter(yaml) do
          {:ok, meta} -> {:ok, meta, body}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :no_frontmatter}
    end
  end

  defp parse_yaml_frontmatter(yaml) do
    yaml
    |> decode_yaml()
    |> case do
      {:ok, decoded} when is_map(decoded) ->
        {:ok, normalize_keys(decoded)}

      {:ok, _decoded} ->
        {:error, :invalid_frontmatter}

      {:error, _reason} ->
        yaml
        |> sanitize_problematic_yaml()
        |> decode_yaml()
        |> case do
          {:ok, decoded} when is_map(decoded) -> {:ok, normalize_keys(decoded)}
          {:ok, _decoded} -> {:error, :invalid_frontmatter}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp decode_yaml(yaml) do
    case YamlElixir.read_from_string(yaml) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  defp sanitize_problematic_yaml(yaml) do
    yaml
    |> String.split(~r/\r?\n/)
    |> Enum.map(fn line ->
      case Regex.run(~r/^([A-Za-z0-9_-]+):\s*([^'"\[{].*:.*)$/, line) do
        [_, key, value] ->
          ~s(#{key}: "#{String.replace(value, "\"", "\\\"")}")

        _ ->
          line
      end
    end)
    |> Enum.join("\n")
  end

  defp normalize_keys(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), normalize_keys(value))
    end)
  end

  defp normalize_keys(list) when is_list(list), do: Enum.map(list, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp read_openai_metadata(skill_dir, skill_name) do
    path = Path.join([skill_dir, "agents", "openai.yaml"])

    case File.read(path) do
      {:ok, contents} ->
        case decode_yaml(contents) do
          {:ok, decoded} when is_map(decoded) ->
            {normalize_keys(decoded), []}

          {:ok, _decoded} ->
            {%{},
             [
               %SkillDiagnostic{
                 level: "warn",
                 code: "invalid_openai_yaml",
                 message: "agents/openai.yaml did not decode to a map and was ignored.",
                 path: path,
                 skill_name: skill_name
               }
             ]}

          {:error, _reason} ->
            {%{},
             [
               %SkillDiagnostic{
                 level: "warn",
                 code: "invalid_openai_yaml",
                 message: "agents/openai.yaml could not be parsed and was ignored.",
                 path: path,
                 skill_name: skill_name
               }
             ]}
        end

      _ ->
        {%{}, []}
    end
  end

  defp maybe_add_name_mismatch(diagnostics, name, parent_name, skill_path) do
    if name == parent_name do
      diagnostics
    else
      [
        %SkillDiagnostic{
          level: "warn",
          code: "name_mismatch",
          message: "Skill name does not match the parent directory name.",
          path: skill_path,
          skill_name: name
        }
        | diagnostics
      ]
    end
  end

  defp maybe_add_name_warning(diagnostics, name, skill_path) do
    if Regex.match?(@name_regex, name) do
      diagnostics
    else
      [
        %SkillDiagnostic{
          level: "warn",
          code: "nonstandard_name",
          message: "Skill name should be lowercase, hyphenated, and 64 characters or fewer.",
          path: skill_path,
          skill_name: name
        }
        | diagnostics
      ]
    end
  end

  defp maybe_add_missing_description(diagnostics, "", skill_path, name) do
    [
      %SkillDiagnostic{
        level: "error",
        code: "missing_description",
        message: "Skill is missing a non-empty description.",
        path: skill_path,
        skill_name: name
      }
      | diagnostics
    ]
  end

  defp maybe_add_missing_description(diagnostics, _description, _skill_path, _name),
    do: diagnostics

  defp reference_diagnostics(body, skill_dir, skill_path, skill_name) do
    Regex.scan(~r/\[[^\]]+\]\(([^)]+)\)/, body, capture: :all_but_first)
    |> List.flatten()
    |> Enum.reject(&(String.starts_with?(&1, "http://") or String.starts_with?(&1, "https://")))
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.uniq()
    |> Enum.flat_map(fn relative ->
      expanded = Path.expand(relative, skill_dir)

      if File.exists?(expanded) do
        []
      else
        [
          %SkillDiagnostic{
            level: "warn",
            code: "missing_reference",
            message: "Referenced file #{relative} does not exist.",
            path: skill_path,
            skill_name: skill_name
          }
        ]
      end
    end)
  end

  defp compatibility_diagnostics(meta, openai_metadata, skill_path, skill_name) do
    supported = SkillTarget.ids()

    meta
    |> compatibility_targets(openai_metadata)
    |> Enum.reject(&(&1 in supported))
    |> Enum.map(fn target ->
      %SkillDiagnostic{
        level: "warn",
        code: "unsupported_target",
        message: "Compatibility target #{target} is not supported by ControlKeel.",
        path: skill_path,
        skill_name: skill_name
      }
    end)
  end

  defp compatibility_targets(meta, openai_metadata) do
    raw =
      normalize_list(Map.get(meta, "compatibility")) ++
        normalize_list(get_in(meta, ["metadata", "compatibility_targets"])) ++
        normalize_list(get_in(openai_metadata, ["metadata", "compatibility_targets"]))

    raw
    |> Enum.map(&String.downcase(to_string(&1)))
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_compatibility(nil), do: nil
  defp normalize_compatibility(value) when is_binary(value), do: value
  defp normalize_compatibility(value) when is_list(value), do: Enum.join(value, ", ")
  defp normalize_compatibility(value), do: inspect(value)

  defp normalize_required_tools(meta, allowed_tools) do
    metadata_tools =
      normalize_list(get_in(meta, ["metadata", "ck_mcp_tools"])) ++
        normalize_list(get_in(meta, ["dependencies", "mcp_tools"]))

    metadata_tools
    |> Kernel.++(allowed_tools)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_list(nil), do: []

  defp normalize_list(value) when is_binary(value),
    do: String.split(value, ~r/[\s,]+/, trim: true)

  defp normalize_list(value) when is_list(value), do: Enum.flat_map(value, &normalize_list/1)
  defp normalize_list(value), do: [to_string(value)]

  defp discover_resources(skill_dir) do
    Enum.flat_map(@resource_dirs, fn subdir ->
      path = Path.join(skill_dir, subdir)

      if File.dir?(path) do
        walk_resource_dir(path, subdir)
      else
        []
      end
    end)
    |> Enum.sort()
  end

  defp walk_resource_dir(root, prefix) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: false)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(fn file ->
      relative = Path.relative_to(file, root)
      Path.join(prefix, relative)
    end)
  end

  defp classify_source(skill_path) do
    cond do
      String.contains?(skill_path, "/priv/skills/") -> "builtin"
      String.contains?(skill_path, "/.github/skills/") -> "github"
      String.contains?(skill_path, "/.claude/skills/") -> "claude"
      String.contains?(skill_path, "/.copilot/skills/") -> "copilot"
      true -> "agents"
    end
  end

  defp normalize_nil(""), do: nil
  defp normalize_nil(value), do: value

  defp truthy?(value), do: value in [true, "true", "True", 1, "1", "yes"]
  defp falsey?(value), do: value in [false, "false", "False", 0, "0", "no"]
end
