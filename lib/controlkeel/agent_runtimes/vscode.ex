defmodule ControlKeel.AgentRuntimes.VSCode do
  @moduledoc false

  @behaviour ControlKeel.AgentRuntimes.Runtime

  @impl true
  def id, do: "vscode"

  @impl true
  def runtime_transport, do: "vscode_companion"

  @impl true
  def runtime_auth_owner, do: "workspace"

  @impl true
  def runtime_session_support do
    %{"create" => false, "fork" => false, "resume" => false, "streaming" => false}
  end

  @impl true
  def runtime_review_transport, do: "vscode_ipc"

  @impl true
  def runtime_provider_hint(_project_root, _opts), do: nil
end
