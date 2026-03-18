defmodule ControlKeel.Policy.Rule do
  @enforce_keys [:id, :category, :severity, :action, :plain_message, :matcher]
  defstruct [:id, :category, :severity, :action, :plain_message, :matcher]

  @type t :: %__MODULE__{
          id: String.t(),
          category: String.t(),
          severity: String.t(),
          action: String.t(),
          plain_message: String.t(),
          matcher: map()
        }
end
