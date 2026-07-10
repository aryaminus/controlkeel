defmodule ControlKeel.MCP.Tools.CkAttach do
  @moduledoc """
  MCP tool: ck_attach

  Closes the gap for users who installed ControlKeel via a one-line copy-paste
  MCP-add command (Claude `mcp add-json`, Cursor deeplink, etc.) instead of
  running `controlkeel attach <host>`. Those users get the tool surface but
  miss the host-specific artifacts:

    - SessionStart / PreToolUse / PostToolUse / UserPromptSubmit hooks
    - Skills (`.claude/skills`, `.codex/skills`, `.agents/skills`)
    - Slash commands (e.g. `/controlkeel-completion-review`)
    - `AGENTS.md` / `CLAUDE.md` governance preamble
    - Subagent profiles (where applicable)

  This tool runs the same machinery as `controlkeel attach <host>` from
  inside the MCP session. Idempotent — re-running on a fully attached
  project just refreshes artifacts to the current version.

  ## Arguments

    - `host` (required): one of the attachable agent IDs. Use
      `ck_attach` error output to see the supported host IDs.
    - `project_root` (optional): absolute path to the project. Defaults to
      `CK_PROJECT_ROOT` or the MCP server's working directory.
    - `scope` (optional): `"project"` (default) or `"user"`. Scope selects
      host artifact destinations; it never widens project authorization.

  ## Trust boundary

  The requested project must exist and remain within the canonical
  `CK_PROJECT_ROOT` for every scope. Project artifacts stay within that root.
  Hosts whose MCP registration is user-managed may also update their documented
  host config path; user scope may additionally install native host artifacts.
  This tool does not run network egress.
  """

  alias ControlKeel.Agent.Integration
  alias ControlKeel.CLI

  def call(arguments) when is_map(arguments) do
    with {:ok, host} <- require_host(arguments),
         {:ok, _integration} <- validate_host(host),
         {:ok, scope} <- validate_scope(arguments),
         {:ok, project_root} <- resolve_project_root(arguments) do
      options =
        []
        |> Keyword.put(:project_root, project_root)
        |> Keyword.put(:scope, scope)

      command = %{
        command: :attach,
        args: [host],
        options: Enum.into(options, %{})
      }

      case CLI.run_command(command, project_root) do
        {:ok, lines} ->
          {:ok,
           %{
             "host" => host,
             "status" => "attached",
             "lines" => lines,
             "next_steps" => next_steps()
           }}

        {:error, message} ->
          {:error, {:invalid_arguments, message}}
      end
    end
  end

  def call(_), do: {:error, {:invalid_arguments, "arguments must be a JSON object"}}

  defp require_host(%{"host" => host}) when is_binary(host) and host != "" do
    {:ok, host}
  end

  defp require_host(_), do: {:error, {:invalid_arguments, "host is required"}}

  defp validate_host(host) do
    attachable = Integration.attachable_ids()

    cond do
      host not in attachable ->
        {:error,
         {:invalid_arguments, "unknown host: #{host}. Supported: #{Enum.join(attachable, ", ")}"}}

      Integration.get(host) == nil ->
        {:error, {:invalid_arguments, "host #{host} is not in the integration catalog"}}

      true ->
        {:ok, Integration.get(host)}
    end
  end

  defp validate_scope(arguments) do
    case Map.get(arguments, "scope", "project") do
      scope when scope in ["project", "user"] -> {:ok, scope}
      scope -> {:error, {:invalid_arguments, "invalid scope: #{inspect(scope)}"}}
    end
  end

  defp resolve_project_root(arguments) do
    boundary = System.get_env("CK_PROJECT_ROOT") || File.cwd!()
    requested = Map.get(arguments, "project_root") || boundary

    cond do
      not is_binary(requested) or requested == "" ->
        {:error, {:invalid_arguments, "project_root must be a non-empty absolute path"}}

      Path.type(requested) != :absolute ->
        {:error, {:invalid_arguments, "project_root must be an absolute path"}}

      not File.dir?(boundary) ->
        {:error, {:invalid_arguments, "CK_PROJECT_ROOT must be an existing directory"}}

      not File.dir?(requested) ->
        {:error, {:invalid_arguments, "project_root must be an existing directory"}}

      not within_root?(canonical_path(boundary), canonical_path(requested)) ->
        {:error,
         {:invalid_arguments, "project_root must stay within #{canonical_path(boundary)}"}}

      true ->
        {:ok, canonical_path(requested)}
    end
  end

  defp within_root?(root, path) do
    # Use Path.relative_to/2 for cross-platform separator handling.
    # Returns the path unchanged when not inside root, so equality means "outside".
    Path.relative_to(path, root) != path
  end

  defp canonical_path(path) do
    # Walk each path component and resolve symlinks at every level.
    # :file.read_link_all/1 only resolves when the *leaf* is a symlink;
    # intermediate symlinks return :einval, which would leave the path
    # unresolved and defeat the boundary check.
    #
    # Path.split/1 returns the root/drive as the first element (e.g. ["C:/" | rest]
    # on Windows, ["/" | rest] on Unix). Use it as the initial accumulator instead
    # of hardcoding "/" so drive letters are preserved on Windows.
    [root | components] =
      path
      |> Path.expand()
      |> Path.split()

    Enum.reduce(components, root, fn component, acc ->
      candidate = Path.join(acc, component)
      resolve_component(candidate, MapSet.new())
    end)
  end

  defp resolve_component(candidate, seen) do
    cond do
      MapSet.member?(seen, candidate) ->
        # Symlink loop — return as-is; caller's File.dir?/1 check will reject.
        candidate

      true ->
        case :file.read_link(String.to_charlist(candidate)) do
          {:ok, target_charlist} ->
            # :file.read_link/1 returns a charlist; convert to binary for Path functions.
            target = List.to_string(target_charlist)

            absolute =
              if Path.type(target) == :absolute,
                do: target,
                else: Path.join(Path.dirname(candidate), target)

            resolve_component(Path.expand(absolute), MapSet.put(seen, candidate))

          {:error, _} ->
            candidate
        end
    end
  end

  defp next_steps do
    [
      "Run ck_context to load mission state.",
      "Optional: controlkeel cloud connect --enroll https://controlkeel.com",
      "Verify: controlkeel cloud doctor"
    ]
  end
end
