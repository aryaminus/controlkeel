defmodule ControlKeel.Runtime.BoundedLoopVerifier do
  @moduledoc """
  Adapter contract for independent bounded-loop verification.

  Verifiers observe worker output but must not mutate the workspace or redefine
  the persisted objective.
  """

  @type result :: %{String.t() => term()}

  @callback verify(context :: map(), worker_result :: map()) ::
              {:ok, result()} | {:error, term()}
end
