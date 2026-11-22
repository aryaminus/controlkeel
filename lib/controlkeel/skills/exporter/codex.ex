defmodule ControlKeel.Skills.Exporter.Codex do
  @moduledoc false

  alias ControlKeel.CLI.CodexConfig
  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    compat_skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, compat_skill_root)

    config_path = Path.join(root, ".codex/config.toml")
    File.mkdir_p!(Path.dirname(config_path))

    {:ok, _} =
      CodexConfig.write(config_path, %{
        command: E.mcp_command(project_root, opts),
        args: E.mcp_args(project_root, opts)
      })

    agent_root = Path.join(root, ".codex/agents")
    File.mkdir_p!(agent_root)

    agent_paths =
      E.codex_agent_specs(project_root, skills, opts)
      |> Enum.map(fn {filename, contents} ->
        path = Path.join(agent_root, filename)
        File.write!(path, contents)
        path
      end)

    diff_command_path = Path.join(root, ".codex/commands/controlkeel-diff-review.md")
    File.mkdir_p!(Path.dirname(diff_command_path))
    File.write!(diff_command_path, E.codex_diff_review_command_contents())

    completion_command_path = Path.join(root, ".codex/commands/controlkeel-completion-review.md")
    File.mkdir_p!(Path.dirname(completion_command_path))
    File.write!(completion_command_path, E.codex_completion_review_command_contents())

    review_command_path = Path.join(root, ".codex/commands/controlkeel-review.md")
    File.write!(review_command_path, E.codex_review_command_contents())

    annotate_command_path = Path.join(root, ".codex/commands/controlkeel-annotate.md")
    File.write!(annotate_command_path, E.codex_annotate_command_contents())

    last_command_path = Path.join(root, ".codex/commands/controlkeel-last.md")
    File.write!(last_command_path, E.codex_last_command_contents())

    hooks_path = Path.join(root, ".codex/hooks.json")
    File.write!(hooks_path, Jason.encode!(E.codex_hooks_manifest(), pretty: true) <> "\n")

    hook_dir = Path.join(root, ".codex/hooks")
    File.mkdir_p!(hook_dir)

    for {name, contents_fn} <- E.codex_hook_scripts() do
      path = Path.join(hook_dir, name)
      File.write!(path, contents_fn.())
      File.chmod!(path, 0o755)
    end

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    instructions_path = Path.join(root, "AGENTS.md")
    File.write!(instructions_path, E.instructions_only_contents("codex", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => compat_skill_root, "kind" => "skills"},
        %{"path" => config_path, "kind" => "config"},
        %{"path" => diff_command_path, "kind" => "command"},
        %{"path" => completion_command_path, "kind" => "command"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => hook_dir, "kind" => "hooks"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => instructions_path, "kind" => "instructions"}
      ] ++ Enum.map(agent_paths, &%{"path" => &1, "kind" => "agent"}),
      [
        "Codex loads skills from .agents/skills.",
        "Use .codex/config.toml to register the ControlKeel MCP server and operator role with Codex.",
        "Copy the generated `.codex/agents/*.toml` files into your Codex agents directory if you want preconfigured CK operator, reviewer, or docs-researcher agents.",
        "Use .codex/commands/ for browser-reviewed review, annotate, last, diff, and completion approval flows.",
        "Use `.codex/hooks.json` with `.codex/hooks/` to load repo-scoped Codex lifecycle hooks for session context, Bash validation, and stop-time warnings.",
        "Use .mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end
end
