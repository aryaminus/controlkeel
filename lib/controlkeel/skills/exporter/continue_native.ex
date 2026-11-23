defmodule ControlKeel.Skills.Exporter.ContinueNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    prompt_path = Path.join(root, ".continue/prompts/controlkeel.md")
    File.mkdir_p!(Path.dirname(prompt_path))
    File.write!(prompt_path, E.continue_prompt_contents())

    plan_prompt_path = Path.join(root, ".continue/prompts/controlkeel-plan.md")
    File.write!(plan_prompt_path, E.continue_plan_prompt_contents())

    review_prompt_path = Path.join(root, ".continue/prompts/controlkeel-review.md")
    File.write!(review_prompt_path, E.continue_review_prompt_contents())

    headless_prompt_path = Path.join(root, ".continue/prompts/controlkeel-headless.md")
    File.write!(headless_prompt_path, E.continue_headless_prompt_contents())

    command_path = Path.join(root, ".continue/commands/controlkeel-review.prompt")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.continue_command_contents())

    submit_command_path = Path.join(root, ".continue/commands/controlkeel-submit-plan.prompt")
    File.write!(submit_command_path, E.continue_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".continue/commands/controlkeel-annotate.prompt")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Continue", "continue", ".continue/annotate.md")
    )

    last_command_path = Path.join(root, ".continue/commands/controlkeel-last.prompt")
    File.write!(last_command_path, E.host_last_command_contents("Continue"))

    config_path = Path.join(root, ".continue/mcp.json")

    File.write!(
      config_path,
      Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n"
    )

    mcp_server_path = Path.join(root, ".continue/mcpServers/controlkeel.yaml")
    File.mkdir_p!(Path.dirname(mcp_server_path))
    File.write!(mcp_server_path, E.continue_mcp_server_contents(project_root, opts))

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("continue", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => prompt_path, "kind" => "instructions"},
        %{"path" => plan_prompt_path, "kind" => "instructions"},
        %{"path" => review_prompt_path, "kind" => "instructions"},
        %{"path" => headless_prompt_path, "kind" => "instructions"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => config_path, "kind" => "mcp"},
        %{"path" => mcp_server_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.agents/skills`, `.continue/prompts`, and `.continue/commands` into the repo for Continue-native plan, review, and headless guidance.",
        "Use `.continue/mcpServers/controlkeel.yaml` for MCP registration or `.continue/mcp.json` as the portable fallback."
      ]
    )
  end
end
