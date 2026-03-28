defmodule ControlKeel.Skills.SkillDefinition do
  @moduledoc false

  defstruct [
    :name,
    :description,
    :path,
    :skill_dir,
    :body,
    :metadata,
    :scope,
    :source,
    :license,
    :compatibility,
    :compatibility_targets,
    :allowed_tools,
    :required_mcp_tools,
    :disable_model_invocation,
    :user_invocable,
    :resources,
    :diagnostics,
    :openai,
    :agent_metadata,
    :install_state
  ]
end
