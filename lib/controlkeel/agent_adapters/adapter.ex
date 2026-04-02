defmodule ControlKeel.AgentAdapters.Adapter do
  @moduledoc false

  @callback id() :: String.t()
  @callback install(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback export(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback artifact_manifest(keyword()) :: [String.t()]
  @callback review_submission_contract() :: map()
  @callback phase_contract() :: map()
  @callback host_capabilities() :: map()
  @callback skill_targets() :: [map()]
end
