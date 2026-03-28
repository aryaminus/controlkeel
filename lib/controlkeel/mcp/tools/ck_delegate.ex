defmodule ControlKeel.MCP.Tools.CkDelegate do
  @moduledoc false

  alias ControlKeel.AgentExecution

  def call(arguments) when is_map(arguments) do
    project_root = Map.get(arguments, "project_root", File.cwd!())

    case AgentExecution.delegate(arguments, project_root) do
      {:ok, result} -> {:ok, result}
      {:error, {:invalid_arguments, reason}} -> {:error, {:invalid_arguments, reason}}
      {:error, {:policy_blocked, reason}} -> {:error, {:policy_violation, reason}}
      {:error, reason} -> {:error, reason}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
