defmodule ControlKeel.Runtime.BoundedLoopRollback do
  @moduledoc "Adapter contract for audited iteration checkpoints and rollback."

  @callback prepare(context :: map()) :: {:ok, term()} | {:error, term()}
  @callback rollback(context :: map(), checkpoint :: term(), reason :: String.t()) ::
              :ok | {:error, term()}
end
