defmodule ControlKeel.MCP.Tools.CkRegressionResult do
  @moduledoc false

  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    Mission.record_regression_result(arguments)
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
