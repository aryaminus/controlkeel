defmodule ControlKeel.Project.VirtualWorkspace do
  @moduledoc false

  @ignored_dirs MapSet.new(
                  ~w(.git .elixir_ls _build deps node_modules vendor priv/static tmp log)
                )

  alias ControlKeel.Mission
  alias ControlKeel.Project.WorkspaceContext

  @max_read_lines 400
  @max_find_results 200
  @max_grep_matches 200

  def resolve_root(session_id, fallback_root \\ File.cwd!()) when is_integer(session_id) do
    effective_fallback =
      if is_binary(fallback_root) and fallback_root != "", do: fallback_root, else: File.cwd!()

    case Mission.get_session(session_id) do
      nil ->
        {:error, {:invalid_arguments, "Session not found"}}

      session ->
        root = WorkspaceContext.resolve_project_root(session, effective_fallback)

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

  def list(session_id, path, opts \\ []) when is_integer(session_id) and is_binary(path) do
    with {:ok, root} <- resolve_root(session_id, Keyword.get(opts, :fallback_root)),
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
    with {:ok, root} <- resolve_root(session_id, Keyword.get(opts, :fallback_root)),
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
    with {:ok, root} <- resolve_root(session_id, Keyword.get(opts, :fallback_root)),
         {:ok, scope_path, scope_relative_path} <- safe_path(root, Keyword.get(opts, :path, ".")),
         {:ok, limit} <- normalize_positive_integer(Keyword.get(opts, :limit, 50), "limit") do
      normalized_query = String.downcase(String.trim(query))
      matcher = query_matcher(normalized_query)

      matches =
        walk_paths(scope_path)
        |> Stream.map(&Path.relative_to(&1, root))
        |> Stream.reject(&(&1 == "."))
        |> Stream.filter(fn relative ->
          path = String.downcase(relative)
          basename = relative |> Path.basename() |> String.downcase()
          matcher.(path, basename) != []
        end)
        |> Enum.map(&find_candidate(root, &1, normalized_query, matcher))
        |> Enum.sort_by(fn {sort_key, _result} -> sort_key end)
        |> Enum.take(min(limit, @max_find_results))
        |> Enum.map(fn {_sort_key, result} -> result end)
        |> Enum.with_index(1)
        |> Enum.map(fn {result, rank} -> Map.put(result, "rank", rank) end)

      {:ok,
       %{
         "project_root" => root,
         "path" => scope_relative_path,
         "query" => normalized_query,
         "match_mode" => if(matcher_glob?(normalized_query), do: "glob", else: "substring"),
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
    with {:ok, root} <- resolve_root(session_id, Keyword.get(opts, :fallback_root)),
         {:ok, scope_path, scope_relative_path} <- safe_path(root, Keyword.get(opts, :path, ".")),
         {:ok, limit} <- normalize_positive_integer(Keyword.get(opts, :limit, 50), "limit") do
      max_matches = min(limit, @max_grep_matches)

      with {:ok, matches} <- grep_matches(root, scope_path, query, opts, max_matches) do
        {annotated_matches, file_summaries} = annotate_grep_results(matches)

        {:ok,
         %{
           "project_root" => root,
           "path" => scope_relative_path,
           "query" => query,
           "matches" => annotated_matches,
           "files" => file_summaries,
           "file_count" => length(file_summaries),
           "count" => length(annotated_matches),
           "limited" => length(annotated_matches) == max_matches,
           "read_only" => true,
           "virtual_filesystem" => true,
           "tool" => "grep"
         }}
      end
    end
  end

  defp find_candidate(root, relative, normalized_query, matcher) do
    absolute = Path.join(root, relative)
    basename = relative |> Path.basename() |> String.downcase()
    path = String.downcase(relative)
    bases = matcher.(path, basename)

    match_quality = match_quality(path, basename, normalized_query)
    path_depth = path_depth(relative)
    orientation_hint = orientation_hint(relative)
    orientation_penalty = orientation_penalty(orientation_hint)

    sort_key =
      {orientation_penalty + match_quality, path_depth, String.length(relative), relative}

    result = %{
      "path" => relative,
      "type" => file_type(absolute),
      "matched_on" => bases,
      "path_depth" => path_depth,
      "orientation_hint" => orientation_hint,
      "orientation_score" =>
        orientation_score(orientation_penalty, match_quality, path_depth, relative)
    }

    {sort_key, result}
  end

  # Query matchers: substring (default) or glob when the query contains
  # `*`, `?` (or `**`). Globs translate to anchored, case-insensitive
  # regexes matched against both the project-relative path and the
  # basename. `*` stays within one path segment; `**` crosses segments.
  defp matcher_glob?(query) do
    String.contains?(query, "*") or String.contains?(query, "?")
  end

  defp query_matcher(query) do
    if matcher_glob?(query) do
      case compile_glob_regex(query) do
        {:ok, regex} -> glob_matcher(regex)
        :error -> substring_matcher(query)
      end
    else
      substring_matcher(query)
    end
  end

  defp substring_matcher(query) do
    fn path, basename ->
      []
      |> maybe_add_match_basis(String.contains?(path, query), "path")
      |> maybe_add_match_basis(String.contains?(basename, query), "basename")
      |> Enum.reverse()
    end
  end

  defp glob_matcher(regex) do
    fn path, basename ->
      []
      |> maybe_add_match_basis(Regex.match?(regex, path), "path")
      |> maybe_add_match_basis(Regex.match?(regex, basename), "basename")
      |> Enum.reverse()
    end
  end

  defp compile_glob_regex(glob) do
    source =
      glob
      |> String.split("**")
      |> Enum.map_join(".*", &translate_glob_segment/1)

    case Regex.compile("^" <> source <> "$", "i") do
      {:ok, regex} -> {:ok, regex}
      {:error, _reason} -> :error
    end
  end

  defp translate_glob_segment(segment) do
    segment
    |> String.split("*")
    |> Enum.map_join("[^/]*", &translate_glob_question/1)
  end

  defp translate_glob_question(part) do
    part
    |> String.split("?")
    |> Enum.map_join("[^/]", &Regex.escape/1)
  end

  defp annotate_grep_results(matches) do
    counts = Enum.frequencies_by(matches, & &1["path"])

    annotated_matches =
      matches
      |> Enum.with_index(1)
      |> Enum.map(fn {match, rank} ->
        path = match["path"] || ""

        match
        |> Map.put("rank", rank)
        |> Map.put("file_match_count", Map.get(counts, path, 1))
        |> Map.put("path_depth", path_depth(path))
        |> Map.put("orientation_hint", orientation_hint(path))
      end)

    file_summaries =
      annotated_matches
      |> Enum.group_by(& &1["path"])
      |> Enum.map(fn {path, file_matches} ->
        %{
          "path" => path,
          "match_count" => length(file_matches),
          "first_line_number" => file_matches |> Enum.map(& &1["line_number"]) |> Enum.min(),
          "path_depth" => path_depth(path),
          "orientation_hint" => orientation_hint(path)
        }
      end)
      |> Enum.sort_by(fn summary ->
        {
          orientation_penalty(summary["orientation_hint"]),
          summary["path_depth"],
          summary["first_line_number"],
          summary["path"]
        }
      end)
      |> Enum.with_index(1)
      |> Enum.map(fn {summary, rank} -> Map.put(summary, "rank", rank) end)

    {annotated_matches, file_summaries}
  end

  defp match_quality(_path, basename, query) when basename == query, do: 0

  defp match_quality(_path, basename, query) do
    stem = basename |> Path.rootname() |> String.downcase()

    cond do
      stem == query -> 0
      String.starts_with?(basename, query) -> 10
      String.contains?(basename, query) -> 20
      true -> 40
    end
  end

  defp maybe_add_match_basis(bases, true, basis), do: [basis | bases]
  defp maybe_add_match_basis(bases, false, _basis), do: bases

  defp path_depth(""), do: 0
  defp path_depth(path), do: path |> Path.split() |> length()

  defp orientation_hint(path) do
    parts = path |> String.downcase() |> Path.split()

    cond do
      Enum.any?(parts, &(&1 in ["deps", "vendor", "node_modules", ".git"])) -> "vendor"
      Enum.any?(parts, &(&1 in ["_build", "priv", "tmp", "dist", "build"])) -> "build"
      Enum.any?(parts, &(&1 in ["test", "tests", "spec", "specs"])) -> "test"
      true -> "source"
    end
  end

  defp orientation_penalty("source"), do: 0
  defp orientation_penalty("test"), do: 100
  defp orientation_penalty("build"), do: 150
  defp orientation_penalty("vendor"), do: 200
  defp orientation_penalty(_hint), do: 250

  defp orientation_score(orientation_penalty, match_quality, path_depth, relative) do
    penalty =
      orientation_penalty + match_quality + path_depth * 3 + div(String.length(relative), 20)

    max(0, 1_000 - penalty)
  end

  defp grep_matches(root, scope_path, query, opts, max_matches) do
    if rg = System.find_executable("rg") do
      grep_with_rg(rg, root, scope_path, query, opts, max_matches)
    else
      grep_with_elixir(root, scope_path, query, opts, max_matches)
    end
  end

  defp grep_with_rg(rg, root, scope_path, query, opts, max_matches) do
    scope_arg = Path.relative_to(scope_path, root)

    args =
      ([
         "--json",
         "--line-number",
         "--hidden"
       ] ++ ignored_rg_globs())
      |> maybe_add_arg(Keyword.get(opts, :ignore_case, false), "-i")
      |> maybe_add_arg(Keyword.get(opts, :fixed_strings, true), "-F")
      |> Kernel.++([query, if(scope_arg == "", do: ".", else: scope_arg)])

    case System.cmd(rg, args, cd: root, stderr_to_stdout: true) do
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
        # walk_children already prunes ignored entries (deps, .git, tmp, etc.)
        # at every recursion level via ignored_entry?/1 on the directory entry
        # name. Do NOT re-check the absolute path here — ignored_path?/1 on a
        # full path like /tmp/foo/lib/x.ex would wrongly reject every file
        # under a /tmp/ parent.
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

  defp ignored_rg_globs do
    Enum.flat_map(@ignored_dirs, fn dir -> ["--glob", "!#{dir}/**"] end)
  end

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
          # Bolt: Avoid intermediate list allocation for line counting
          length(:binary.matches(contents, "\n")) + 1
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

          if ignored_entry?(entry) do
            []
          else
            if File.dir?(path) do
              Stream.concat([path], walk_children(path))
            else
              [path]
            end
          end
        end)

      _ ->
        []
    end
  end

  defp ignored_entry?(entry), do: MapSet.member?(@ignored_dirs, entry)

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
