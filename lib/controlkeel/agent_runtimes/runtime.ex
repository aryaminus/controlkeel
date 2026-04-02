defmodule ControlKeel.AgentRuntimes.Runtime do
  @moduledoc false

  @callback id() :: String.t()
  @callback runtime_transport() :: String.t()
  @callback runtime_auth_owner() :: String.t()
  @callback runtime_session_support() :: map()
  @callback runtime_review_transport() :: String.t()
  @callback runtime_provider_hint(String.t(), keyword()) :: map() | nil
end
