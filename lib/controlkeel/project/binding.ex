defmodule ControlKeel.Project.Binding do
  @moduledoc false

  alias ControlKeel.Project.Root
  alias ControlKeel.Runtime.Paths
  alias ControlKeel.Utils

  @version 1
  @compile_source_root Path.expand("../../..", __DIR__)

  def read(project_root \\ File.cwd!()) do
    path = path(project_root)

    with true <- File.exists?(path) || {:error, :not_found},
         {:ok, payload} <- File.read(path),
         {:ok, decoded} <- Jason.decode(payload),
         :ok <- validate(decoded, canonical_root(project_root)) do
      {:ok, decoded}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def write(attrs, project_root \\ File.cwd!()) when is_map(attrs) do
    root = canonical_root(project_root)
    binding = normalized_binding(attrs, root)
    path = path(root)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, Jason.encode!(binding, pretty: true) <> "\n") do
      {:ok, binding}
    end
  end

  def write_effective(attrs, project_root \\ File.cwd!(), opts \\ []) when is_map(attrs) do
    case Keyword.get(opts, :mode, :project) do
      :ephemeral -> write_ephemeral(attrs, project_root)
      _ -> write(attrs, project_root)
    end
  end

  def path(project_root \\ File.cwd!()) do
    Path.join(canonical_root(project_root), "controlkeel/project.json")
  end

  def ephemeral_path(project_root \\ File.cwd!()) do
    project_root
    |> canonical_root()
    |> Paths.ephemeral_binding_path()
  end

  def wrapper_dir(project_root \\ File.cwd!()) do
    Path.join(canonical_root(project_root), "controlkeel/bin")
  end

  def mcp_wrapper_path(project_root \\ File.cwd!()) do
    Path.join(wrapper_dir(project_root), wrapper_filename())
  end

  @gitignore_block_start "# ControlKeel managed (do not edit) - artifacts that must not be committed"
  @gitignore_block_end "# End ControlKeel managed"

  # CK-owned paths written into a user's repo that must never be committed.
  # `controlkeel/` holds the binding plus a machine-specific MCP wrapper (it
  # embeds an absolute CK_PROJECT_ROOT), and `.controlkeel/` holds local tool
  # usage telemetry. Callers may pass extra entries (e.g. project-scope agent
  # dirs created by `attach`) which are merged into the same managed block.
  @gitignore_entries ["/controlkeel/", "/.controlkeel/", "/.agents/skills/"]

  def ensure_gitignore(project_root \\ File.cwd!(), extra_entries \\ []) do
    path = Path.join(canonical_root(project_root), ".gitignore")

    existing =
      case File.read(path) do
        {:ok, value} -> value
        {:error, :enoent} -> ""
      end

    ignored_dirs = anchored_ignored_dirs(existing)

    entries =
      (@gitignore_entries ++
         existing_block_entries(existing) ++
         normalize_gitignore_entries(extra_entries))
      |> Enum.uniq()
      |> Enum.reject(&covered_by_parent?(&1, ignored_dirs))

    updated = upsert_gitignore_block(existing, build_gitignore_block(entries))

    if updated == existing, do: :ok, else: File.write(path, updated)
  end

  # Entries already inside a managed block, so repeated calls (e.g. attaching
  # several agents) accumulate their dirs rather than overwriting each other.
  defp existing_block_entries(existing) do
    with [_, rest] <- String.split(existing, @gitignore_block_start, parts: 2),
         [body, _tail] <- String.split(rest, @gitignore_block_end, parts: 2) do
      body
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    else
      _ -> []
    end
  end

  # Anchored directory rules (e.g. `/.claude/`) anywhere in the file. An
  # entry beneath one of them is already ignored and would only add noise.
  # Git keeps leading spaces as part of a pattern, so only trailing
  # whitespace is trimmed. A directory that any `!` rule mentions is not
  # trusted, because the negation may re-include it or its children.
  defp anchored_ignored_dirs(existing) do
    lines = existing |> String.split("\n") |> Enum.map(&String.trim_trailing/1)
    negations = Enum.filter(lines, &String.starts_with?(&1, "!"))

    lines
    |> Enum.filter(&(String.starts_with?(&1, "/") and String.ends_with?(&1, "/")))
    |> Enum.reject(fn dir ->
      name = String.trim_leading(dir, "/")
      Enum.any?(negations, &String.contains?(&1, name))
    end)
  end

  defp covered_by_parent?(entry, ignored_dirs) do
    Enum.any?(ignored_dirs, &(&1 != entry and String.starts_with?(entry, &1)))
  end

  defp normalize_gitignore_entries(entries) when is_list(entries) do
    entries
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_gitignore_entries(_), do: []

  defp build_gitignore_block(entries) do
    @gitignore_block_start <> "\n" <> Enum.join(entries, "\n") <> "\n" <> @gitignore_block_end
  end

  # Replace an existing managed block in place (so the entry set stays current)
  # or append a fresh one, preserving all user-authored .gitignore content.
  defp upsert_gitignore_block(existing, block) do
    base =
      case String.split(existing, @gitignore_block_start, parts: 2) do
        [before, rest] ->
          tail =
            case String.split(rest, @gitignore_block_end, parts: 2) do
              [_body, after_block] -> after_block
              [_] -> ""
            end

          String.trim_trailing(before, "\n") <> tail

        [_] ->
          existing
      end
      |> String.trim_trailing("\n")

    if base == "", do: block <> "\n", else: base <> "\n\n" <> block <> "\n"
  end

  def ensure_mcp_wrapper(project_root \\ File.cwd!()) do
    root = canonical_root(project_root)
    path = mcp_wrapper_path(root)
    contents = mcp_wrapper_script_contents(root)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, contents),
         :ok <- maybe_make_executable(path) do
      :ok
    end
  end

  def read_effective(project_root \\ File.cwd!()) do
    case read(project_root) do
      {:ok, binding} ->
        {:ok, binding, :project}

      {:error, :not_found} ->
        case read_ephemeral(project_root) do
          {:ok, binding} -> {:ok, binding, :ephemeral}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_ephemeral(project_root \\ File.cwd!()) do
    project_root
    |> ephemeral_path()
    |> read_path(canonical_root(project_root))
  end

  def write_ephemeral(attrs, project_root \\ File.cwd!()) when is_map(attrs) do
    root = canonical_root(project_root)

    binding =
      attrs
      |> Map.put(
        "bootstrap",
        Map.merge(%{"mode" => "ephemeral"}, Map.get(attrs, "bootstrap", %{}))
      )
      |> normalized_binding(root)

    path = ephemeral_path(root)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, Jason.encode!(binding, pretty: true) <> "\n") do
      {:ok, binding}
    end
  end

  def update_attached_agent(binding, agent_key, attrs) when is_map(binding) and is_map(attrs) do
    attached =
      attrs
      |> Utils.stringify_keys()
      |> Map.put("controlkeel_version", controlkeel_version())

    attached_agents =
      binding
      |> Map.get("attached_agents", %{})
      |> Map.put(agent_key, attached)

    Map.put(binding, "attached_agents", attached_agents)
  end

  def put_provider_override(project_root \\ File.cwd!(), attrs) when is_map(attrs) do
    with {:ok, binding, mode} <- read_effective(project_root),
         updated <- Map.put(binding, "provider_override", Utils.stringify_keys(attrs)),
         {:ok, written} <- write_effective(updated, project_root, mode: mode) do
      {:ok, written}
    end
  end

  def get_tool_groups(project_root \\ File.cwd!()) do
    case read_effective(project_root) do
      {:ok, binding, _mode} ->
        binding["tool_groups"]

      {:error, _reason} ->
        nil
    end
  end

  def put_tool_groups(project_root \\ File.cwd!(), groups) when is_list(groups) do
    with {:ok, binding, mode} <- read_effective(project_root),
         updated <- Map.put(binding, "tool_groups", groups),
         {:ok, written} <- write_effective(updated, project_root, mode: mode) do
      {:ok, written}
    end
  end

  def bootstrap_summary(project_root \\ File.cwd!()) do
    case read_effective(project_root) do
      {:ok, binding, mode} ->
        bootstrap = binding["bootstrap"] || %{}

        %{
          "mode" => Atom.to_string(mode),
          "binding_path" => binding_path(project_root, mode),
          "project_root" => binding["project_root"],
          "auto_bootstrapped" => bootstrap["auto_bootstrapped"] || false
        }

      {:error, _reason} ->
        %{
          "mode" => "none",
          "binding_path" => nil,
          "project_root" => canonical_root(project_root),
          "auto_bootstrapped" => false
        }
    end
  end

  def mcp_command_spec(project_root \\ File.cwd!(), opts \\ []) do
    root = canonical_root(project_root)

    if Keyword.get(opts, :portable, false) do
      # Global/shared host configs (e.g. ~/.config/opencode/opencode.json,
      # ~/.codex/config.toml at user scope, Cursor/Windsurf/Goose global MCP
      # files) must NOT embed a project-specific absolute wrapper path. Such a
      # wrapper can live in a temp or moved folder and break MCP for every
      # project that shares the global config. The MCP server resolves the
      # project root from CK_PROJECT_ROOT or its working directory at runtime
      # (see ControlKeel.MCP.Server.stdio_project_root/0).
      %{
        command: default_cli_command(),
        args: ["mcp"],
        binding_mode: binding_mode(root)
      }
    else
      wrapper = mcp_wrapper_path(root)

      if File.exists?(wrapper) do
        %{command: wrapper, args: [], binding_mode: "project"}
      else
        %{
          command: default_cli_command(),
          args: ["mcp", "--project-root", root],
          binding_mode: binding_mode(root)
        }
      end
    end
  end

  defp normalized_binding(attrs, project_root) do
    %{
      "version" => @version,
      "project_root" => project_root,
      "workspace_id" => attrs["workspace_id"] || attrs[:workspace_id],
      "session_id" => attrs["session_id"] || attrs[:session_id],
      "org_id" => attrs["org_id"] || attrs[:org_id],
      "agent" => attrs["agent"] || attrs[:agent],
      "attached_agents" => attrs["attached_agents"] || attrs[:attached_agents] || %{},
      "bootstrap" =>
        attrs["bootstrap"] ||
          attrs[:bootstrap] ||
          %{"mode" => "project", "auto_bootstrapped" => false},
      "provider_override" => attrs["provider_override"] || attrs[:provider_override],
      "tool_groups" => attrs["tool_groups"] || attrs[:tool_groups] || nil
    }
  end

  defp validate(
         %{
           "version" => @version,
           "project_root" => project_root,
           "workspace_id" => workspace_id,
           "session_id" => session_id,
           "agent" => agent,
           "attached_agents" => attached_agents
         } = binding,
         expected_root
       )
       when is_binary(project_root) and is_integer(workspace_id) and is_integer(session_id) and
              is_binary(agent) and is_map(attached_agents) do
    case Map.get(binding, "org_id") do
      org_id when is_nil(org_id) or is_integer(org_id) ->
        if project_root == expected_root, do: :ok, else: {:error, :project_root_mismatch}

      _other ->
        {:error, :invalid_binding}
    end
  end

  defp validate(_binding, _expected_root), do: {:error, :invalid_binding}

  defp read_path(path, expected_root) do
    with true <- File.exists?(path) || {:error, :not_found},
         {:ok, payload} <- File.read(path),
         {:ok, decoded} <- Jason.decode(payload),
         :ok <- validate(decoded, expected_root) do
      {:ok, decoded}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp canonical_root(project_root) do
    Root.resolve(project_root)
  end

  defp mcp_wrapper_script_contents(root) do
    case :os.type() do
      {:win32, _} ->
        wrapper_contents(root)

      _ ->
        if controlkeel_source_app?(root),
          do: stdio_launcher_template!(),
          else: wrapper_contents(root)
    end
  end

  # When bootstrapping inside the ControlKeel Elixir checkout, install the same
  # stdio-safe launcher as `bin/controlkeel-mcp` (mix ck.mcp, JSON-only stdout,
  # stdin forwarded). The generic wrapper only runs `controlkeel mcp` and is
  # wrong here: older Python shims stalled OpenCode, and Mix lock chatter breaks Cursor.
  defp controlkeel_source_app?(root) do
    File.exists?(Path.join(root, "mix.exs")) &&
      File.exists?(Path.join(root, "lib/controlkeel/application.ex"))
  end

  defp stdio_launcher_template! do
    path = Application.app_dir(:controlkeel, "priv/mcp/controlkeel_stdio_launcher.sh")

    case File.read(path) do
      {:ok, body} ->
        body

      {:error, reason} ->
        raise "ControlKeel MCP stdio launcher template missing at #{path}: #{inspect(reason)}"
    end
  end

  defp wrapper_filename do
    case :os.type() do
      {:win32, _} -> "controlkeel-mcp.cmd"
      _ -> "controlkeel-mcp"
    end
  end

  defp wrapper_contents(project_root) do
    escaped_root = String.replace(project_root, "\"", "\\\"")
    default = default_cli_command()
    # When the resolved default is a dev/build artifact (mix release script wrapper,
    # _build/..., erts- shim), prefer the bare command name. MCP hosts inherit their
    # own PATH and can resolve `controlkeel` to an installed Burrito binary, but a
    # hard-coded build path locks the wrapper to whichever machine generated it.
    default = if dev_or_build_path?(default), do: cli_candidate_name(), else: default
    escaped_default = String.replace(default, "\"", "\\\"")

    source_launcher = source_repo_mcp_launcher_path() || ""
    escaped_source_launcher = String.replace(source_launcher, "\"", "\\\"")

    case :os.type() do
      {:win32, _} ->
        """
        @echo off
        setlocal
        set "CK_PROJECT_ROOT=#{escaped_root}"
        if "%CONTROLKEEL_BIN%"=="" (
          set "CONTROLKEEL_BIN=#{escaped_default}"
        )
        "%CONTROLKEEL_BIN%" mcp --project-root "#{escaped_root}" %*
        """

      _ ->
        """
        #!/usr/bin/env sh
        set -eu

        export CK_PROJECT_ROOT="#{escaped_root}"
        BINARY="${CONTROLKEEL_BIN:-#{escaped_default}}"
        SOURCE_LAUNCHER="#{escaped_source_launcher}"

        if [ -n "$BINARY" ]; then
          if [ -x "$BINARY" ] || command -v "$BINARY" >/dev/null 2>&1; then
            exec "$BINARY" mcp --project-root "#{escaped_root}" "$@"
          fi
        fi

        if [ -n "$SOURCE_LAUNCHER" ] && [ -x "$SOURCE_LAUNCHER" ]; then
          exec "$SOURCE_LAUNCHER" "$@"
        fi

        echo "controlkeel MCP wrapper could not find a runnable controlkeel binary. Install ControlKeel or set CONTROLKEEL_BIN to an absolute executable path." >&2
        exit 1
        """
    end
  end

  defp maybe_make_executable(path) do
    case :os.type() do
      {:win32, _} -> :ok
      _ -> File.chmod(path, 0o755)
    end
  end

  defp binding_path(project_root, :project), do: path(project_root)
  defp binding_path(project_root, :ephemeral), do: ephemeral_path(project_root)

  defp binding_mode(project_root) do
    case read_effective(project_root) do
      {:ok, _binding, mode} -> Atom.to_string(mode)
      _ -> "none"
    end
  end

  @doc false
  def resolve_cli_executable(path) when is_binary(path) do
    cond do
      burrito_erts_shim?(path) ->
        find_path_native_cli() || unwrap_burrito_sibling(path) || path

      true ->
        path
    end
  end

  @doc false
  def cli_executable_command, do: default_cli_command()

  @doc false
  def burrito_erts_shim?(path) when is_binary(path) do
    String.contains?(path, ".burrito") and String.contains?(path, "erts-")
  end

  def burrito_erts_shim?(_), do: false

  @doc false
  def mcp_wrapper_default_cli(project_root \\ File.cwd!()) do
    path = mcp_wrapper_path(project_root)

    with true <- File.exists?(path),
         {:ok, body} <- File.read(path) do
      case Regex.run(~r/BINARY="\$\{CONTROLKEEL_BIN:-([^}]+)\}"/, body) do
        [_, cli_path] -> {:ok, String.trim(cli_path, "\"")}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  @doc false
  def mcp_wrapper_cli_runnable?(project_root \\ File.cwd!()) do
    case mcp_wrapper_default_cli(project_root) do
      {:ok, cli_path} -> not burrito_erts_shim?(cli_path)
      _ -> false
    end
  end

  defp default_cli_command do
    candidate = cli_candidate_name()
    found = System.find_executable(candidate) || candidate
    resolve_cli_executable(found)
  end

  defp cli_candidate_name do
    case :os.type() do
      {:win32, _} -> "controlkeel.exe"
      _ -> "controlkeel"
    end
  end

  # Detect dev/build artifact paths so the MCP wrapper can fall back to a bare
  # `controlkeel` command on PATH. We don't want to hard-code machine-specific
  # build paths into wrappers that ship to other machines.
  @doc false
  def dev_or_build_path?(""), do: true
  def dev_or_build_path?(nil), do: true

  def dev_or_build_path?(path) do
    String.contains?(path, "/_build/") or
      String.contains?(path, "/.burrito/") or
      String.contains?(path, "/erts-") or
      String.contains?(path, "/deps/") or
      String.contains?(path, "/bin/mix")
  end

  # Burrito ERTS layout: <install_dir>/.burrito/controlkeel_erts-<vsn>/bin/controlkeel
  # The native binary sits at: <install_dir>/controlkeel
  defp unwrap_burrito_sibling(path) do
    bin_dir = Path.dirname(path)
    erts_dir = Path.dirname(bin_dir)
    dot_burrito_dir = Path.dirname(erts_dir)
    install_dir = Path.dirname(dot_burrito_dir)
    native = Path.join(install_dir, Path.basename(path))

    if File.exists?(native), do: native, else: nil
  end

  defp find_path_native_cli do
    name = cli_candidate_name()

    (System.get_env("PATH") || "")
    |> String.split(path_separator(), trim: true)
    |> Enum.find_value(fn dir ->
      candidate = Path.join(dir, name)

      if File.exists?(candidate) and not burrito_erts_shim?(candidate) do
        candidate
      end
    end)
  end

  defp path_separator do
    case :os.type() do
      {:win32, _} -> ";"
      _ -> ":"
    end
  end

  defp source_repo_mcp_launcher_path do
    case :os.type() do
      {:win32, _} ->
        nil

      _ ->
        launcher = Path.join(@compile_source_root, "bin/controlkeel-mcp")
        marker = Path.join(@compile_source_root, "lib/controlkeel/application.ex")

        if File.exists?(launcher) and File.exists?(marker) do
          launcher
        else
          nil
        end
    end
  end

  defp controlkeel_version do
    to_string(Application.spec(:controlkeel, :vsn) || "0.2.0")
  end
end
