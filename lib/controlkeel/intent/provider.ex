defmodule ControlKeel.Intent.Provider do
  @moduledoc false

  @callback compile(map(), keyword()) ::
              {:ok, map(), map()}
              | {:skip, atom()}
              | {:error, atom() | binary() | Exception.t()}
end
