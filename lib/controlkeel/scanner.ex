defmodule ControlKeel.Scanner do
  defmodule Finding do
    @enforce_keys [
      :id,
      :severity,
      :category,
      :rule_id,
      :decision,
      :plain_message,
      :location,
      :metadata
    ]
    defstruct [
      :id,
      :severity,
      :category,
      :rule_id,
      :decision,
      :plain_message,
      :location,
      :metadata
    ]
  end

  defmodule Result do
    @enforce_keys [:allowed, :decision, :summary, :findings, :scanned_at]
    defstruct [:allowed, :decision, :summary, :findings, :scanned_at, :advisory]
  end
end
