defmodule ControlKeel.MCP.Tools.CkExecuteCode do
  @moduledoc false

  alias ControlKeel.Runtime.CodeExecutor

  def call(arguments), do: CodeExecutor.call(arguments)
end
