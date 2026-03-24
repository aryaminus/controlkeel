defmodule ControlKeel.ProjectBinding do
  @moduledoc false

  alias ControlKeel.RuntimePaths

  @version 1

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
    contents = wrapper_contents(root)

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
    attached_agents =
      binding
      |> Map.get("attached_agents", %{})
      |> Map.put(agent_key, attrs)

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
    expanded = Path.expand(project_root)

    case :os.type() do
      {:win32, _} ->
        expanded

      _ ->
        case System.find_executable("pwd") do
          nil ->
            expanded

          executable ->
            case System.cmd(executable, ["-P"], cd: expanded, stderr_to_stdout: true) do
              {realpath, 0} -> String.trim(realpath)
              {_output, _code} -> expanded
            end
        end
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

    case :os.type() do
      {:win32, _} ->
        """
        @echo off
        setlocal
        if "%CONTROLKEEL_BIN%"=="" (
          set "CONTROLKEEL_BIN=controlkeel.exe"
        )
        "%CONTROLKEEL_BIN%" mcp --project-root "#{escaped_root}" %*
        """

      _ ->
        """
        #!/usr/bin/env sh
        set -eu

        BINARY="${CONTROLKEEL_BIN:-controlkeel}"
        exec "$BINARY" mcp --project-root "#{escaped_root}" "$@"
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
    case :os.type() do
      {:win32, _} -> "controlkeel.exe"
      _ -> "controlkeel"
    end
  end
end
