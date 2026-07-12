defmodule ControlKeel.MCP.Tools.CkLoop do
  @moduledoc false

  alias ControlKeel.Runtime.BoundedLoop

  def call(arguments) when is_map(arguments) do
    case Map.get(arguments, "mode", "status") do
      "create" -> BoundedLoop.create(arguments)
      "record" -> BoundedLoop.record(arguments)
      "status" -> BoundedLoop.status(arguments)
      "stop" -> BoundedLoop.stop(arguments)
      "promote" -> BoundedLoop.promote(arguments)
      _ -> {:error, {:invalid_arguments, "mode must be create, record, status, stop, or promote"}}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
