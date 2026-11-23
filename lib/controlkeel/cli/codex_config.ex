defmodule ControlKeel.CLI.CodexConfig do
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

    updated =
      existing
      |> upsert_managed_block(managed_block(command, args, opts))
      |> ensure_feature_flag("codex_hooks", "true")

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, updated) do
      {:ok, config_path}
    end
  end

  @doc """
  Merges an exported Codex `config.toml` into `config_path`: only the
  ControlKeel managed block is replaced, and the hooks feature flag is
  ensured. Everything the user wrote outside the block is preserved.
  """
  def merge_export(config_path, export_contents) when is_binary(export_contents) do
    block =
      case split_managed_block(export_contents) do
        {:ok, _prefix, _suffix} ->
          [_, rest] = String.split(export_contents, @managed_start, parts: 2)
          [inner, _] = String.split(rest, @managed_end, parts: 2)
          @managed_start <> inner <> @managed_end

        :error ->
          nil
      end

    existing =
      case File.read(config_path) do
        {:ok, contents} -> contents
        _ -> ""
      end

    updated =
      if(block, do: upsert_managed_block(existing, block), else: existing)
      |> ensure_feature_flag("codex_hooks", "true")

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, updated) do
      {:ok, config_path}
    end
  end

  @doc """
  Reverse of write/3: strip the controlkeel managed block from config.toml,
  preserving any user-authored content outside the block. Deletes the file if
  nothing else remains. Idempotent and best-effort.
  """
  def remove(config_path) do
    case File.read(config_path) do
      {:ok, contents} ->
        case split_managed_block(contents) do
          {:ok, prefix, suffix} ->
            remaining = join_sections(prefix, "", suffix) |> String.trim()

            if remaining == "" do
              File.rm(config_path)
            else
              File.write(config_path, remaining <> "\n")
            end

          :error ->
            :ok
        end

      _ ->
        :ok
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
      {:ok, prefix, suffix} ->
        join_sections(strip_unmarked_ck_tables(prefix), block, strip_unmarked_ck_tables(suffix))

      :error ->
        join_sections(strip_unmarked_ck_tables(existing), block, "")
    end
  end

  # TOML forbids declaring a table twice. A ControlKeel table written without
  # the managed markers (for example by `Integration.mcp_install_command/1`)
  # would otherwise sit beside the managed block and break the whole file, so
  # the managed block becomes the only declaration.

  defp strip_unmarked_ck_tables(text) do
    {kept, _skipping} =
      text
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], false}, fn line, {acc, skipping} ->
        case toml_header(line) do
          nil ->
            if skipping, do: {acc, true}, else: {[line | acc], false}

          header ->
            if ck_table?(header), do: {acc, true}, else: {[line | acc], false}
        end
      end)

    kept |> Enum.reverse() |> Enum.join("\n")
  end

  # A table header as its list of key segments, so `[ mcp_servers."controlkeel" ]`
  # and `[mcp_servers.controlkeel]` compare equal while a quoted segment such
  # as `"controlkeel.backup"` stays one segment. Returns nil for non-headers.
  defp toml_header(line) do
    trimmed = String.trim(line)

    with "[" <> rest <- trimmed,
         {:ok, segments, tail} <- parse_key_segments(String.trim_leading(rest, "["), []),
         true <- tail_is_header_end?(tail) do
      segments
    else
      _ -> nil
    end
  end

  defp tail_is_header_end?(tail) do
    case tail |> String.trim_leading("]") |> String.trim() do
      "" -> true
      "#" <> _comment -> true
      _ -> false
    end
  end

  defp parse_key_segments(input, acc) do
    input = String.trim_leading(input)

    {segment, rest} =
      case input do
        "\"" <> quoted -> take_quoted(quoted, "\"")
        "'" <> quoted -> take_quoted(quoted, "'")
        bare -> take_bare(bare)
      end

    case segment do
      nil ->
        :error

      segment ->
        case String.trim_leading(rest) do
          "." <> more -> parse_key_segments(more, [segment | acc])
          "]" <> _ = tail -> {:ok, Enum.reverse([segment | acc]), tail}
          _ -> :error
        end
    end
  end

  defp take_quoted(input, quote) do
    case String.split(input, quote, parts: 2) do
      [segment, rest] -> {segment, rest}
      _ -> {nil, ""}
    end
  end

  defp take_bare(input) do
    case Regex.run(~r/^([A-Za-z0-9_-]+)(.*)$/s, input) do
      [_, segment, rest] -> {segment, rest}
      _ -> {nil, ""}
    end
  end

  defp ck_table?(["mcp_servers", "controlkeel" | _]), do: true
  defp ck_table?(["agents", "controlkeel_operator" | _]), do: true
  defp ck_table?(_segments), do: false

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

  defp ensure_feature_flag(contents, flag, value) do
    lines = String.split(contents, "\n", trim: false)

    {updated_lines, _in_features?, _found_flag?, found_features?} =
      Enum.reduce(lines, {[], false, false, false}, fn line,
                                                       {acc, in_features?, found_flag?,
                                                        found_features?} ->
        trimmed = String.trim(line)
        header = toml_header(line)
        table_header? = header != nil
        entering_features? = header == ["features"]
        leaving_features? = in_features? and table_header? and not entering_features?
        flag_line? = in_features? and String.match?(trimmed, ~r/^#{Regex.escape(flag)}\s*=/)

        acc =
          cond do
            leaving_features? and not found_flag? ->
              acc ++ ["#{flag} = #{value}", line]

            flag_line? ->
              acc ++ ["#{flag} = #{value}"]

            true ->
              acc ++ [line]
          end

        in_features? =
          cond do
            entering_features? -> true
            leaving_features? -> false
            true -> in_features?
          end

        found_flag? = found_flag? or flag_line?
        found_features? = found_features? or entering_features?

        {acc, in_features?, found_flag?, found_features?}
      end)
      |> then(fn {acc, in_features?, found_flag?, found_features?} ->
        acc =
          if in_features? and not found_flag? do
            acc ++ ["#{flag} = #{value}"]
          else
            acc
          end

        {acc, in_features?, found_flag?, found_features?}
      end)

    cond do
      found_features? ->
        Enum.join(updated_lines, "\n")

      String.trim(contents) == "" ->
        "[features]\n#{flag} = #{value}\n"

      true ->
        Enum.join(updated_lines ++ ["", "[features]", "#{flag} = #{value}"], "\n")
    end
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
