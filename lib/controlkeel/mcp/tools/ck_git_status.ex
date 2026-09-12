defmodule ControlKeel.MCP.Tools.CkGitStatus do
  @moduledoc false

  alias ControlKeel.Git.Workflow
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    project_root = Arguments.project_root(arguments)

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

    Workflow.status(project_root, opts)
  catch
    {:invalid_session_id, reason} -> {:error, reason}
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
