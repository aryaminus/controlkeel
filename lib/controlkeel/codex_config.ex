defmodule ControlKeel.CodexConfig do
  @moduledoc false

  @managed_start "# controlkeel:start"
  @managed_end "# controlkeel:end"
  @default_agent_key "controlkeel_operator"
  @default_agent_config "./agents/controlkeel-operator.toml"
  @default_description "Operate inside a ControlKeel-governed project with CK skills and MCP tools."

  def user_config_path do
    home = System.get_env("HOME") || System.user_home!()

    case :os.type() do
      {:win32, _} ->
        Path.join([System.get_env("APPDATA") || home, ".codex", "config.toml"])

      _ ->
        Path.join([home, ".codex", "config.toml"])
    end
  end

  def project_config_path(project_root) do
    Path.join([Path.expand(project_root), ".codex", "config.toml"])
  end

  def path_for_scope(project_root, "project"), do: project_config_path(project_root)
  def path_for_scope(_project_root, "user"), do: user_config_path()

  def write(config_path, command_spec, opts \\ []) do
    command = command_spec[:command] || command_spec["command"]
    args = command_spec[:args] || command_spec["args"] || []

    existing =
      case File.read(config_path) do
        {:ok, contents} -> contents
        _ -> ""
      end

    updated = upsert_managed_block(existing, managed_block(command, args, opts))

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, updated) do
      {:ok, config_path}
    end
  end

  defp managed_block(command, args, opts) do
    agent_key = Keyword.get(opts, :agent_key, @default_agent_key)
    agent_config = Keyword.get(opts, :agent_config, @default_agent_config)
    description = Keyword.get(opts, :description, @default_description)

    [
      @managed_start,
      "[mcp_servers.controlkeel]",
      "command = #{toml_string(command)}",
      "args = #{toml_array(args)}",
      "",
      "[agents.#{agent_key}]",
      "description = #{toml_string(description)}",
      "config_file = #{toml_string(agent_config)}",
      @managed_end
    ]
    |> Enum.join("\n")
  end

  defp upsert_managed_block(existing, block) do
    case split_managed_block(existing) do
      {:ok, prefix, suffix} -> join_sections(prefix, block, suffix)
      :error -> join_sections(existing, block, "")
    end
  end

  defp split_managed_block(existing) do
    case String.split(existing, @managed_start, parts: 2) do
      [prefix, rest] ->
        case String.split(rest, @managed_end, parts: 2) do
          [_, suffix] -> {:ok, prefix, suffix}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp join_sections(prefix, block, suffix) do
    [String.trim(prefix), String.trim(block), String.trim(suffix)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp toml_array(values) when is_list(values) do
    "[#{Enum.map_join(values, ", ", &toml_string/1)}]"
  end

  defp toml_string(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    ~s("#{escaped}")
  end
end
