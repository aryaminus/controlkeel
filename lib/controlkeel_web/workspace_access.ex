defmodule ControlKeelWeb.WorkspaceAccess do
  @moduledoc """
  Shared org-access gate for workspace-scoped LiveViews (issues #83, #141 R1).

  Collapses the per-view `check_workspace_access` copies into one decision
  point. Authority resolves from `(user, workspace org)` — never from the
  ambient `current_org_id` cookie, which production never writes:

    * local mode → `:ok` (single-user deployment; also fixes the tab pages,
      which previously denied every local request);
    * cloud/self_hosted → the workspace must be org-bound and `user` must
      hold an active membership in that org with at least `required_role`
      (`"viewer"` default for read surfaces, `"admin"` for the workspace
      admin tabs).

  Returns `:ok` or `{:error, reason}` with `:unbound` (workspace has no
  org), `:forbidden` (no active membership — includes missing user), or
  `:needs_admin` (member below the required role). Callers map these to
  their page's user-facing messages.
  """

  alias ControlKeel.Accounts
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Runtime.Mode

  @type denial :: :unbound | :forbidden | :needs_admin
  @spec check(Workspace.t(), map() | nil, String.t()) :: :ok | {:error, denial()}
  def check(%Workspace{} = workspace, user, required_role \\ "viewer") do
    cond do
      Mode.current() == :local -> :ok
      is_nil(workspace.org_id) -> {:error, :unbound}
      true -> check_membership(workspace, user, required_role)
    end
  end

  defp check_membership(%Workspace{org_id: ws_org}, %{id: user_id}, required_role)
       when is_integer(ws_org) and is_integer(user_id) do
    case Accounts.get_active_membership(user_id, ws_org) do
      nil ->
        {:error, :forbidden}

      %Accounts.Membership{role: role} ->
        if Accounts.role_at_least?(role, required_role),
          do: :ok,
          else: {:error, :needs_admin}
    end
  end

  defp check_membership(_workspace, _user, _required_role), do: {:error, :forbidden}
end
