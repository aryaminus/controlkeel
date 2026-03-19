defmodule ControlKeel.Skills.Registry do
  @moduledoc """
  Discovers and catalogs AgentSkills from standard skill directories.

  Scan order (highest precedence first — project-level overrides user-level,
  user-level overrides built-in):

    1. <project>/.agents/skills/   — project-level, cross-client standard
    2. <project>/.claude/skills/   — project-level, Claude Code compatible
    3. ~/.agents/skills/           — user-level, cross-client
    4. ~/.claude/skills/           — user-level, Claude Code compatible
    5. priv/skills/                — built-in ControlKeel governance skills

  Each skill is a directory containing a SKILL.md file with YAML frontmatter
  per the AgentSkills open format (https://agentskills.io/specification).
  """

  @doc "Return the full skill catalog for a project root (or global if nil)."
  def catalog(project_root \\ nil) do
    project_root
    |> skill_dirs()
    |> Enum.flat_map(&scan_dir/1)
    |> deduplicate_by_name()
  end

  @doc "Look up a single skill entry by name."
  def get(name, project_root \\ nil) do
    Enum.find(catalog(project_root), &(&1.name == name))
  end

  @doc """
  Generate the <available_skills> XML block suitable for injection into
  an agent's system prompt per the AgentSkills specification.
  """
  def prompt_block(project_root \\ nil) do
    skills = catalog(project_root)

    if skills == [] do
      ""
    else
      entries =
        Enum.map(skills, fn s ->
          "  <skill>\n    <name>#{s.name}</name>\n    <description>#{xml_escape(s.description)}</description>\n    <location>#{s.path}</location>\n  </skill>"
        end)

      "<available_skills>\n#{Enum.join(entries, "\n")}\n</available_skills>"
    end
  end

  # ─── Private ──────────────────────────────────────────────────────────────────

  defp skill_dirs(nil) do
    [
      user_path("~/.agents/skills"),
      user_path("~/.claude/skills"),
      priv_skills_dir()
    ]
    |> Enum.filter(&File.dir?/1)
  end

  defp skill_dirs(project_root) do
    expanded = Path.expand(project_root)

    [
      Path.join(expanded, ".agents/skills"),
      Path.join(expanded, ".claude/skills"),
      user_path("~/.agents/skills"),
      user_path("~/.claude/skills"),
      priv_skills_dir()
    ]
    |> Enum.filter(&File.dir?/1)
  end

  defp scan_dir(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          skill_dir = Path.join(dir, entry)
          skill_path = Path.join(skill_dir, "SKILL.md")

          if File.dir?(skill_dir) and File.exists?(skill_path) do
            case parse_skill(skill_path) do
              {:ok, skill} -> [skill]
              _ -> []
            end
          else
            []
          end
        end)

      _ ->
        []
    end
  end

  defp parse_skill(skill_path) do
    with {:ok, content} <- File.read(skill_path),
         {:ok, meta, body} <- extract_frontmatter(content) do
      name =
        Map.get(meta, "name") ||
          skill_path |> Path.dirname() |> Path.basename()

      description = Map.get(meta, "description", "")

      {:ok,
       %{
         name: name,
         description: description,
         path: skill_path,
         body: body,
         metadata: Map.get(meta, "metadata", %{}),
         license: Map.get(meta, "license"),
         compatibility: Map.get(meta, "compatibility"),
         allowed_tools: parse_allowed_tools(Map.get(meta, "allowed-tools", "")),
         scope: classify_scope(skill_path)
       }}
    end
  end

  defp extract_frontmatter(content) do
    case Regex.run(~r/\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*\r?\n(.*)\z/s, content,
           capture: :all_but_first
         ) do
      [yaml, body] ->
        {:ok, parse_yaml_frontmatter(yaml), String.trim(body)}

      _ ->
        {:error, :no_frontmatter}
    end
  end

  # Minimal YAML parser for the AgentSkills frontmatter subset.
  # Handles: flat key: value pairs, metadata: sub-map, allowed-tools: space-delimited.
  defp parse_yaml_frontmatter(yaml) do
    lines = String.split(yaml, ~r/\r?\n/)

    {result, _pending_key} =
      Enum.reduce(lines, {%{}, nil}, fn line, {acc, pending_key} ->
        cond do
          # Indented sub-entry (belongs to pending block key like `metadata:`)
          pending_key != nil and Regex.match?(~r/^[ \t]+\S/, line) ->
            trimmed = String.trim(line)

            case String.split(trimmed, ":", parts: 2) do
              [k, v] ->
                sub = Map.get(acc, pending_key, %{})
                entry = Map.put(sub, String.trim(k), unquote_value(String.trim(v)))
                {Map.put(acc, pending_key, entry), pending_key}

              _ ->
                {acc, pending_key}
            end

          # Top-level key with no inline value — block header
          Regex.match?(~r/^\S[^:]*:\s*$/, line) ->
            key = line |> String.split(":") |> List.first() |> String.trim()
            {Map.put(acc, key, %{}), key}

          # Top-level key: value
          Regex.match?(~r/^\S[^:]*:[ \t]+/, line) ->
            [k | rest] = String.split(line, ":", parts: 2)
            v = rest |> Enum.join(":") |> String.trim() |> unquote_value()
            {Map.put(acc, String.trim(k), v), nil}

          true ->
            {acc, pending_key}
        end
      end)

    result
  end

  defp unquote_value(v) do
    cond do
      String.starts_with?(v, "\"") and String.ends_with?(v, "\"") ->
        String.slice(v, 1..(byte_size(v) - 2))

      String.starts_with?(v, "'") and String.ends_with?(v, "'") ->
        String.slice(v, 1..(byte_size(v) - 2))

      true ->
        v
    end
  end

  defp parse_allowed_tools(nil), do: []
  defp parse_allowed_tools(""), do: []

  defp parse_allowed_tools(tools) when is_binary(tools),
    do: String.split(tools, ~r/\s+/, trim: true)

  defp classify_scope(path) do
    home = System.user_home!()
    priv = priv_skills_dir()

    cond do
      String.starts_with?(path, priv) -> "builtin"
      String.starts_with?(path, home) -> "user"
      true -> "project"
    end
  end

  defp deduplicate_by_name(skills) do
    # First occurrence wins (project > user > builtin per scan order)
    skills
    |> Enum.reduce({[], MapSet.new()}, fn skill, {acc, seen} ->
      if MapSet.member?(seen, skill.name) do
        {acc, seen}
      else
        {[skill | acc], MapSet.put(seen, skill.name)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp user_path(path), do: Path.expand(path)

  defp priv_skills_dir do
    :controlkeel
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("skills")
  end

  defp xml_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
