defmodule ControlKeelWeb.OrgAccess do
  @moduledoc """
  Shared org-access gate for org-scoped LiveViews.

  Authority resolves from `(user, org)` and follows the same pattern as the
  workspace gate:

    * local mode → `:ok`
    * cloud/self_hosted → the org must be valid and the user must hold an
      active membership in that org with at least `required_role`

  Returns `:ok` or `{:error, reason}` with `:forbidden` (missing user or no
  active membership) and `:needs_admin` (member below the required role).
  Callers map these to their page's user-facing messages.
  """

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Runtime.Mode

  @type denial :: :forbidden | :needs_admin
  @spec check(Org.t(), map() | nil, String.t()) :: :ok | {:error, denial()}
  def check(org, user, required_role \\ "viewer")

  def check(%Org{} = org, user, required_role) do
    cond do
      Mode.current() == :local -> :ok
      is_nil(user) -> {:error, :forbidden}
      true -> check_membership(org, user, required_role)
    end
  end

  def check(_org, _user, _required_role), do: {:error, :forbidden}

  defp check_membership(%Org{id: org_id}, %{id: user_id}, required_role)
       when is_integer(org_id) and is_integer(user_id) do
    case Accounts.get_active_membership(user_id, org_id) do
      nil ->
        {:error, :forbidden}

      %Accounts.Membership{role: role} ->
        if Accounts.role_at_least?(role, required_role),
          do: :ok,
          else: {:error, :needs_admin}
    end
  end

  defp check_membership(_org, _user, _required_role), do: {:error, :forbidden}
end
