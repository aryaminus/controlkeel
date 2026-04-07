defmodule ControlKeel.VirtualWorkspace do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.WorkspaceContext

  @max_read_lines 400
  @max_find_results 200
  @max_grep_matches 200

  def resolve_root(session_id, fallback_root \\ File.cwd!()) when is_integer(session_id) do
    case Mission.get_session(session_id) do
      nil ->
        {:error, {:invalid_arguments, "Session not found"}}

      session ->
        root = WorkspaceContext.resolve_project_root(session, fallback_root)

        cond do
          is_nil(root) ->
            {:error, {:invalid_arguments, "No bound project root was found for this session"}}

          not File.dir?(root) ->
            {:error, {:invalid_arguments, "The bound project root is not available on disk"}}

          true ->
            {:ok, Path.expand(root)}
        end
    end
  end

  def list(session_id, path, _opts \\ []) when is_integer(session_id) and is_binary(path) do
    with {:ok, root} <- resolve_root(session_id),
         {:ok, absolute_path, relative_path} <- safe_path(root, path),
         :ok <- ensure_directory(absolute_path),
         {:ok, entries} <- File.ls(absolute_path) do
      children =
        entries
        |> Enum.sort()
        |> Enum.map(&entry_summary(root, absolute_path, relative_path, &1))

      {:ok,
       %{
         "project_root" => root,
         "path" => relative_path,
         "entries" => children,
         "count" => length(children),
         "read_only" => true,
         "virtual_filesystem" => true,
         "tool" => "ls"
       }}
    end
  end

  def read(session_id, path, opts \\ []) when is_integer(session_id) and is_binary(path) do
    with {:ok, root} <- resolve_root(session_id),
         {:ok, absolute_path, relative_path} <- safe_path(root, path),
         :ok <- ensure_regular_file(absolute_path),
         {:ok, contents} <- File.read(absolute_path),
         :ok <- ensure_text(contents),
         {:ok, start_line} <-
           normalize_positive_integer(Keyword.get(opts, :start_line, 1), "start_line"),
         {:ok, max_lines} <-
           normalize_positive_integer(Keyword.get(opts, :max_lines, @max_read_lines), "max_lines") do
      lines = String.split(contents, "\n", trim: false)
      total_lines = length(lines)
      sliced = Enum.slice(lines, start_line - 1, max_lines)
      end_line = if sliced == [], do: start_line - 1, else: start_line + length(sliced) - 1

      {:ok,
       %{
         "project_root" => root,
         "path" => relative_path,
         "content" => Enum.join(sliced, "\n"),
         "start_line" => start_line,
         "end_line" => end_line,
         "total_lines" => total_lines,
         "truncated" => end_line < total_lines,
         "read_only" => true,
         "virtual_filesystem" => true,
         "tool" => "cat"
       }}
    end
  end

  def find(session_id, query, opts \\ []) when is_integer(session_id) and is_binary(query) do
    with {:ok, root} <- resolve_root(session_id),
         {:ok, scope_path, scope_relative_path} <- safe_path(root, Keyword.get(opts, :path, ".")),
         {:ok, limit} <- normalize_positive_integer(Keyword.get(opts, :limit, 50), "limit") do
      normalized_query = String.downcase(String.trim(query))

      matches =
        walk_paths(scope_path)
        |> Stream.map(&Path.relative_to(&1, root))
        |> Stream.reject(&(&1 == "."))
        |> Stream.filter(&String.contains?(String.downcase(&1), normalized_query))
        |> Enum.take(min(limit, @max_find_results))
        |> Enum.map(fn relative ->
          absolute = Path.join(root, relative)

          %{
            "path" => relative,
            "type" => file_type(absolute)
          }
        end)

      {:ok,
       %{
         "project_root" => root,
         "path" => scope_relative_path,
         "query" => normalized_query,
         "matches" => matches,
         "count" => length(matches),
         "limited" => length(matches) == min(limit, @max_find_results),
         "read_only" => true,
         "virtual_filesystem" => true,
         "tool" => "find"
       }}
    end
  end

  def grep(session_id, query, opts \\ []) when is_integer(session_id) and is_binary(query) do
    with {:ok, root} <- resolve_root(session_id),
         {:ok, scope_path, scope_relative_path} <- safe_path(root, Keyword.get(opts, :path, ".")),
         {:ok, limit} <- normalize_positive_integer(Keyword.get(opts, :limit, 50), "limit") do
      max_matches = min(limit, @max_grep_matches)

      with {:ok, matches} <- grep_matches(root, scope_path, query, opts, max_matches) do
        {:ok,
         %{
           "project_root" => root,
           "path" => scope_relative_path,
           "query" => query,
           "matches" => matches,
           "count" => length(matches),
           "limited" => length(matches) == max_matches,
           "read_only" => true,
           "virtual_filesystem" => true,
           "tool" => "grep"
         }}
      end
    end
  end

  defp grep_matches(root, scope_path, query, opts, max_matches) do
    if rg = System.find_executable("rg") do
      grep_with_rg(rg, root, scope_path, query, opts, max_matches)
    else
      grep_with_elixir(root, scope_path, query, opts, max_matches)
    end
  end

  defp grep_with_rg(rg, root, scope_path, query, opts, max_matches) do
    args =
      [
        "--json",
        "--line-number",
        "--hidden",
        "--glob",
        "!.git"
      ]
      |> maybe_add_arg(Keyword.get(opts, :ignore_case, false), "-i")
      |> maybe_add_arg(Keyword.get(opts, :fixed_strings, true), "-F")
      |> Kernel.++([query, scope_path])

    case System.cmd(rg, args, stderr_to_stdout: true) do
      {output, exit_code} when exit_code in [0, 1] ->
        matches =
          output
          |> String.split("\n", trim: true)
          |> Enum.reduce([], fn line, acc ->
            case Jason.decode(line) do
              {:ok, %{"type" => "match", "data" => data}} ->
                [grep_match(root, data) | acc]

              _ ->
                acc
            end
          end)
          |> Enum.reverse()
          |> Enum.take(max_matches)

        {:ok, matches}

      {output, _exit_code} ->
        {:error, {:invalid_arguments, String.trim(output)}}
    end
  end

  defp grep_with_elixir(root, scope_path, query, opts, max_matches) do
    with {:ok, matcher} <- line_matcher(query, opts) do
      matches =
        scope_path
        |> walk_children()
        |> Stream.reject(&path_within_git?/1)
        |> Stream.filter(&File.regular?/1)
        |> Stream.transform(0, fn path, count ->
          if count >= max_matches do
            {:halt, count}
          else
            case grep_file(root, path, matcher, count, max_matches) do
              [] ->
                {[], count}

              file_matches ->
                {file_matches, count + length(file_matches)}
            end
          end
        end)
        |> Enum.to_list()

      {:ok, matches}
    end
  end

  defp grep_file(root, path, matcher, offset, max_matches) do
    case File.read(path) do
      {:ok, contents} ->
        case ensure_text(contents) do
          :ok ->
            contents
            |> String.split("\n", trim: false)
            |> Enum.with_index(1)
            |> Enum.reduce_while([], fn {line, line_number}, acc ->
              case matcher.(line) do
                [] ->
                  {:cont, acc}

                submatches ->
                  match = %{
                    "path" => Path.relative_to(path, root),
                    "line_number" => line_number,
                    "line" => line,
                    "submatches" => submatches
                  }

                  if offset + length(acc) + 1 >= max_matches do
                    {:halt, [match | acc]}
                  else
                    {:cont, [match | acc]}
                  end
              end
            end)
            |> Enum.reverse()

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp line_matcher(query, opts) do
    ignore_case? = Keyword.get(opts, :ignore_case, false)
    fixed_strings? = Keyword.get(opts, :fixed_strings, true)

    if fixed_strings? do
      needle = maybe_downcase(query, ignore_case?)
      needle_length = String.length(query)

      {:ok,
       fn line ->
         normalized_line = maybe_downcase(line, ignore_case?)

         normalized_line
         |> collect_fixed_string_matches(needle, 0, [])
         |> Enum.map(fn start ->
           %{
             "match" => String.slice(line, start, needle_length),
             "start" => start,
             "end" => start + needle_length
           }
         end)
       end}
    else
      options = if ignore_case?, do: [:caseless], else: []

      case Regex.compile(query, options) do
        {:ok, regex} ->
          {:ok,
           fn line ->
             Regex.scan(regex, line, return: :index)
             |> Enum.map(fn
               [{start, length} | _rest] ->
                 %{
                   "match" => String.slice(line, start, length),
                   "start" => start,
                   "end" => start + length
                 }
             end)
           end}

        {:error, reason} ->
          {:error, {:invalid_arguments, "Invalid regex query: #{inspect(reason)}"}}
      end
    end
  end

  defp collect_fixed_string_matches(_line, "", _offset, acc), do: Enum.reverse(acc)

  defp collect_fixed_string_matches(line, needle, offset, acc) do
    case :binary.match(line, needle) do
      {position, _length} ->
        next_offset = offset + position + max(byte_size(needle), 1)

        remainder =
          binary_part(
            line,
            position + byte_size(needle),
            byte_size(line) - position - byte_size(needle)
          )

        collect_fixed_string_matches(remainder, needle, next_offset, [offset + position | acc])

      :nomatch ->
        Enum.reverse(acc)
    end
  end

  defp maybe_downcase(value, true), do: String.downcase(value)
  defp maybe_downcase(value, false), do: value

  defp path_within_git?(path), do: ".git" in Path.split(path)

  defp safe_path(root, path) do
    candidate =
      path
      |> normalize_user_path()
      |> Path.expand(root)

    cond do
      candidate == root ->
        {:ok, candidate, "."}

      String.starts_with?(candidate, root <> "/") ->
        {:ok, candidate, Path.relative_to(candidate, root)}

      true ->
        {:error, {:invalid_arguments, "Path escapes the bound project root"}}
    end
  end

  defp normalize_user_path(path) do
    case String.trim(path) do
      "" ->
        "."

      value ->
        if String.starts_with?(value, "/"), do: "." <> value, else: value
    end
  end

  defp ensure_directory(path) do
    if File.dir?(path) do
      :ok
    else
      {:error, {:invalid_arguments, "The requested path is not a directory"}}
    end
  end

  defp ensure_regular_file(path) do
    if File.regular?(path) do
      :ok
    else
      {:error, {:invalid_arguments, "The requested path is not a regular file"}}
    end
  end

  defp ensure_text(contents) do
    if String.valid?(contents) and not String.contains?(contents, <<0>>) do
      :ok
    else
      {:error, {:invalid_arguments, "Binary files are not supported by the virtual workspace"}}
    end
  end

  defp normalize_positive_integer(value, _field) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp normalize_positive_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{field}` must be a positive integer"}}
    end
  end

  defp normalize_positive_integer(_value, field),
    do: {:error, {:invalid_arguments, "`#{field}` must be a positive integer"}}

  defp entry_summary(root, absolute_parent, relative_parent, name) do
    absolute_path = Path.join(absolute_parent, name)
    relative_path = normalize_relative_path(relative_parent, name)
    type = file_type(absolute_path)

    stat =
      case File.stat(absolute_path) do
        {:ok, value} -> value
        _ -> nil
      end

    %{
      "name" => name,
      "path" => relative_path,
      "type" => type,
      "size_bytes" => stat && stat.size,
      "line_count" => maybe_line_count(absolute_path, type),
      "project_relative" => Path.relative_to(absolute_path, root)
    }
  end

  defp normalize_relative_path(".", name), do: name
  defp normalize_relative_path(relative_parent, name), do: Path.join(relative_parent, name)

  defp file_type(path) do
    cond do
      File.dir?(path) -> "directory"
      File.regular?(path) -> "file"
      true -> "other"
    end
  end

  defp maybe_line_count(_path, "directory"), do: nil

  defp maybe_line_count(path, "file") do
    case File.read(path) do
      {:ok, contents} ->
        if String.valid?(contents) and not String.contains?(contents, <<0>>) do
          length(String.split(contents, "\n", trim: false))
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp maybe_line_count(_path, _type), do: nil

  defp walk_paths(root) do
    Stream.concat([root], walk_children(root))
  end

  defp walk_children(root) do
    case File.ls(root) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Stream.flat_map(fn entry ->
          path = Path.join(root, entry)

          if File.dir?(path) do
            Stream.concat([path], walk_children(path))
          else
            [path]
          end
        end)

      _ ->
        []
    end
  end

  defp grep_match(root, data) do
    path = get_in(data, ["path", "text"]) || ""

    %{
      "path" => Path.relative_to(path, root),
      "line_number" => data["line_number"],
      "line" => get_in(data, ["lines", "text"]) |> to_string() |> String.trim_trailing("\n"),
      "submatches" =>
        Enum.map(data["submatches"] || [], fn submatch ->
          %{
            "match" => submatch["match"]["text"],
            "start" => submatch["start"],
            "end" => submatch["end"]
          }
        end)
    }
  end

  defp maybe_add_arg(args, true, value), do: args ++ [value]
  defp maybe_add_arg(args, false, _value), do: args
end
