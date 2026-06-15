defmodule ControlKeel.MCP.Tools.CkSkillEvolution do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, session_limit} <- optional_integer(arguments, "session_limit", 5),
         {:ok, same_domain_only} <- optional_boolean(arguments, "same_domain_only", true),
         {:ok, mode} <- mode(arguments),
         {:ok, allow_overwrite} <- optional_boolean(arguments, "allow_overwrite", false),
         {:ok, packet} <-
           Mission.skill_evolution_packet(session_id,
             session_limit: session_limit,
             same_domain_only: same_domain_only,
             current_skill_name: Map.get(arguments, "current_skill_name", "trace-evolved-skill"),
             current_skill_content: Map.get(arguments, "current_skill_content", "")
           ) do
      maybe_install(packet, arguments, mode, allow_overwrite)
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp optional_integer(arguments, key, default) do
    case Map.get(arguments, key, default) do
      value -> normalize_integer(value, key)
    end
  end

  defp optional_boolean(arguments, key, default) do
    case Map.get(arguments, key, default) do
      value when is_boolean(value) -> {:ok, value}
      nil -> {:ok, default}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be a boolean if provided"}}
    end
  end

  defp mode(arguments) do
    case Map.get(arguments, "mode", "preview") do
      value when value in ["preview", "install"] -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`mode` must be `preview` or `install`"}}
    end
  end

  defp maybe_install(packet, _arguments, "preview", _allow_overwrite) do
    {:ok, Map.put(packet, "install", %{"mode" => "preview", "installed" => false})}
  end

  defp maybe_install(packet, arguments, "install", allow_overwrite) do
    with {:ok, project_root} <- project_root(arguments),
         {:ok, skill_name} <-
           safe_skill_name(Map.get(packet, "merge_strategy", %{})["current_skill_name"]),
         {:ok, target_path} <- target_path(project_root, skill_name),
         :ok <- ensure_install_allowed(target_path, allow_overwrite),
         :ok <- File.mkdir_p(Path.dirname(target_path)),
         :ok <- File.write(target_path, packet["suggested_skill_document"] || "") do
      {:ok,
       Map.put(packet, "install", %{
         "mode" => "install",
         "installed" => true,
         "skill_name" => skill_name,
         "path" => target_path,
         "registry_hint" => "Project skills registry discovers .agents/skills/<name>/SKILL.md"
       })}
    else
      {:error, reason} when is_atom(reason) ->
        {:error, {:invalid_arguments, "Skill install filesystem error: #{reason}"}}

      {:error, _} = error ->
        error
    end
  end

  defp project_root(arguments) do
    case Map.get(arguments, "project_root") do
      value when is_binary(value) and value != "" -> {:ok, Path.expand(value)}
      _ -> {:error, {:invalid_arguments, "`project_root` is required when mode=install"}}
    end
  end

  defp safe_skill_name(value) when is_binary(value) do
    name =
      value
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]+/, "-")
      |> String.trim("-")

    if name == "" or name in [".", ".."] do
      {:error, {:invalid_arguments, "`current_skill_name` must contain a safe skill name"}}
    else
      {:ok, name}
    end
  end

  defp safe_skill_name(_), do: {:ok, "trace-evolved-skill"}

  defp target_path(project_root, skill_name) do
    root = Path.expand(project_root)
    path = Path.expand(Path.join([root, ".agents", "skills", skill_name, "SKILL.md"]))

    if String.starts_with?(path, root <> "/") do
      {:ok, path}
    else
      {:error, {:invalid_arguments, "Resolved skill path escapes project_root"}}
    end
  end

  defp ensure_install_allowed(_path, true), do: :ok

  defp ensure_install_allowed(path, false) do
    if File.exists?(path) do
      {:error,
       {:invalid_arguments, "Skill already exists; pass allow_overwrite=true to replace it"}}
    else
      :ok
    end
  end

  defp normalize_integer(value, _key) when is_integer(value), do: {:ok, value}

  defp normalize_integer(value, key) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
    end
  end

  defp normalize_integer(_value, key),
    do: {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
end
