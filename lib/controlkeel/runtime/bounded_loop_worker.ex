defmodule ControlKeel.Runtime.BoundedLoopWorker do
  @moduledoc """
  Adapter contract for one bounded-loop worker iteration.

  Implementations own provider-specific execution and must return evidence from
  a fresh sandbox. The coordinator never grants capabilities or credentials.
  """

  @type context :: map()
  @type result :: %{String.t() => term()}

  @callback run(context()) :: {:ok, result()} | {:error, term()}
end
