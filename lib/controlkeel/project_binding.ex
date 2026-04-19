defmodule ControlKeel.ProjectBinding do
  @moduledoc false

  alias ControlKeel.ProjectRoot
  alias ControlKeel.RuntimePaths

  @version 1
  @compile_source_root Path.expand("../..", __DIR__)

  def read(project_root \\ File.cwd!()) do
    path = path(project_root)

    with true <- File.exists?(path) || {:error, :not_found},
         {:ok, payload} <- File.read(path),
         {:ok, decoded} <- Jason.decode(payload),
         :ok <- validate(decoded, canonical_root(project_root)) do
      {:ok, decoded}
    else
      false -> {:error, :not_found}
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
    |> RuntimePaths.ephemeral_binding_path()
  end

  def wrapper_dir(project_root \\ File.cwd!()) do
    Path.join(canonical_root(project_root), "controlkeel/bin")
  end

  def mcp_wrapper_path(project_root \\ File.cwd!()) do
    Path.join(wrapper_dir(project_root), wrapper_filename())
  end

  def ensure_gitignore(project_root \\ File.cwd!()) do
    path = Path.join(canonical_root(project_root), ".gitignore")
    marker = "/controlkeel"

    contents =
      case File.read(path) do
        {:ok, value} -> value
        {:error, :enoent} -> ""
      end

    if String.contains?(contents, marker) do
      :ok
    else
      separator = if contents == "" or String.ends_with?(contents, "\n"), do: "", else: "\n"
      File.write(path, contents <> separator <> marker <> "\n")
    end
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
      |> stringify_keys()
      |> Map.put("controlkeel_version", controlkeel_version())

    attached_agents =
      binding
      |> Map.get("attached_agents", %{})
      |> Map.put(agent_key, attached)

    Map.put(binding, "attached_agents", attached_agents)
  end

  def put_provider_override(project_root \\ File.cwd!(), attrs) when is_map(attrs) do
    with {:ok, binding, mode} <- read_effective(project_root),
         updated <- Map.put(binding, "provider_override", stringify_keys(attrs)),
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

  def mcp_command_spec(project_root \\ File.cwd!()) do
    root = canonical_root(project_root)
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

  defp normalized_binding(attrs, project_root) do
    %{
      "version" => @version,
      "project_root" => project_root,
      "workspace_id" => attrs["workspace_id"] || attrs[:workspace_id],
      "session_id" => attrs["session_id"] || attrs[:session_id],
      "agent" => attrs["agent"] || attrs[:agent],
      "attached_agents" => attrs["attached_agents"] || attrs[:attached_agents] || %{},
      "bootstrap" =>
        attrs["bootstrap"] ||
          attrs[:bootstrap] ||
          %{"mode" => "project", "auto_bootstrapped" => false},
      "provider_override" => attrs["provider_override"] || attrs[:provider_override]
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
         },
         expected_root
       )
       when is_binary(project_root) and is_integer(workspace_id) and is_integer(session_id) and
              is_binary(agent) and is_map(attached_agents) do
    if project_root == expected_root, do: :ok, else: {:error, :project_root_mismatch}
  end

  defp validate(_binding, _expected_root), do: {:error, :invalid_binding}

  defp read_path(path, expected_root) do
    with true <- File.exists?(path) || {:error, :not_found},
         {:ok, payload} <- File.read(path),
         {:ok, decoded} <- Jason.decode(payload),
         :ok <- validate(decoded, expected_root) do
      {:ok, decoded}
    else
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp canonical_root(project_root) do
    ProjectRoot.resolve(project_root)
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
    escaped_default = String.replace(default_cli_command(), "\"", "\\\"")

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

  defp stringify_keys(attrs) when is_map(attrs) do
    Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp binding_path(project_root, :project), do: path(project_root)
  defp binding_path(project_root, :ephemeral), do: ephemeral_path(project_root)
  defp binding_path(project_root, _mode), do: path(project_root)

  defp binding_mode(project_root) do
    case read_effective(project_root) do
      {:ok, _binding, mode} -> Atom.to_string(mode)
      _ -> "none"
    end
  end

  defp default_cli_command do
    candidate =
      case :os.type() do
        {:win32, _} -> "controlkeel.exe"
        _ -> "controlkeel"
      end

    System.find_executable(candidate) || candidate
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
