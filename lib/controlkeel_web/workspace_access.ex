defmodule ControlKeelWeb.WorkspaceAccess do
  @moduledoc """
  Shared org-access gate for workspace-scoped LiveViews (issues #83, #141 R1).

  Collapses the per-view `check_workspace_access` copies into one decision
  point. Authority resolves from `(user, workspace org)` — never from ambient
  session state:

    * local mode → `:ok` (single-user deployment; also fixes the tab pages,
      which previously denied every local request);
    * cloud/self_hosted → the workspace must be org-bound and `user` must
      hold an active membership in that org with at least `required_role`
      (`"viewer"` default for read surfaces, `"admin"` for the workspace
      admin tabs).

  `check/3` returns `:ok` or `{:error, reason}` with `:unbound` (workspace has
  no org), `:forbidden` (no active membership — includes missing user), or
  `:needs_admin` (member below the required role). Callers map these to
  their page's user-facing messages.

  `check_membership/3` returns `{:ok, membership}` on success so a page can
  keep the membership it was admitted with and let `LiveAuth` evict it when
  that membership is revoked. Local mode has no membership and returns
  `{:ok, nil}`.
  """

  alias ControlKeel.Accounts
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Runtime.Mode

  @type denial :: :unbound | :forbidden | :needs_admin
  @type membership_result ::
          {:ok, Accounts.Membership.t() | nil} | {:error, denial()}

  @spec check(Workspace.t(), map() | nil, String.t()) :: :ok | {:error, denial()}
  def check(%Workspace{} = workspace, user, required_role \\ "viewer") do
    case check_membership(workspace, user, required_role) do
      {:ok, _membership} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @spec check_membership(Workspace.t(), map() | nil, String.t()) :: membership_result()
  def check_membership(%Workspace{} = workspace, user, required_role \\ "viewer") do
    cond do
      Mode.current() == :local -> {:ok, nil}
      is_nil(workspace.org_id) -> {:error, :unbound}
      true -> resolve_membership(workspace, user, required_role)
    end
  end

  defp resolve_membership(%Workspace{org_id: ws_org}, %{id: user_id}, required_role)
       when is_integer(ws_org) and is_integer(user_id) do
    case Accounts.get_active_membership(user_id, ws_org) do
      nil ->
        {:error, :forbidden}

      %Accounts.Membership{role: role} = membership ->
        if Accounts.role_at_least?(role, required_role),
          do: {:ok, membership},
          else: {:error, :needs_admin}
    end
  end

  defp resolve_membership(_workspace, _user, _required_role), do: {:error, :forbidden}
end
