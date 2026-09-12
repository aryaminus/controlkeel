defmodule ControlKeel.MCP.Tools.CkGitCommit do
  @moduledoc false

  alias ControlKeel.Git.Workflow
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    project_root = Arguments.project_root(arguments)
    message = Map.get(arguments, "message")

    if is_nil(message) or message == "" do
      {:error, {:invalid_arguments, "`message` is required"}}
    else
      opts = []

      opts =
        case Map.get(arguments, "session_id") do
          nil ->
            opts

          raw ->
            case Arguments.normalize_integer(raw, "session_id") do
              {:ok, session_id} -> [{:session_id, session_id} | opts]
              {:error, reason} -> throw({:invalid_session_id, reason})
            end
        end

      Workflow.commit(project_root, message, opts)
    end
  catch
    {:invalid_session_id, reason} -> {:error, reason}
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
