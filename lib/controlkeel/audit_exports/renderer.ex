defmodule ControlKeel.AuditExports.Renderer do
  @moduledoc false

  @callback render(binary()) :: {:ok, binary()} | {:error, term()}
end
