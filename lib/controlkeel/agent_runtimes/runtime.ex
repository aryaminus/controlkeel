defmodule ControlKeel.AgentRuntimes.Runtime do
  @moduledoc false

  @type capability :: %{
          policy_gate: boolean(),
          tool_approval: boolean(),
          user_input_pause_resume: boolean(),
          deterministic_event_ids: boolean(),
          replay_safe_delivery: boolean()
        }

  @callback id() :: String.t()
  @callback runtime_transport() :: String.t()
  @callback runtime_auth_owner() :: String.t()
  @callback runtime_session_support() :: map()
  @callback runtime_review_transport() :: String.t()
  @callback runtime_provider_hint(String.t(), keyword()) :: map() | nil
  @callback capabilities() :: capability()
end
