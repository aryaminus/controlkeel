defmodule ControlKeelWeb.OrgAuth do
  @moduledoc """
  Single authority for org-scoped LiveView access.

  Every org-scoped route verifies the same chain from its own URL params:

    org exists → user is an active member → (workspaces) workspace exists
    and belongs to the org → (nested) session belongs to the workspace.

  Call explicitly at the top of `mount`; no `on_mount` assigns magic.
  Local mode is open (existence checks only).
  """

  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo
  alias ControlKeel.Runtime.Mode

  @type role :: nil | String.t()

  @doc """
  Authorize `/:org_slug` routes.

  Returns `{:ok, socket, org, membership}` or `{:halt, socket}` with flash
  and redirect already applied. `role` is nil (any active member) or a
  minimum role such as `"admin"`.
  """
  @spec authorize_org(map(), String.t(), role(), keyword()) ::
          {:ok, map(), map(), map() | nil} | {:halt, map()}
  def authorize_org(socket, slug, role \\ nil, opts \\ []) do
    forbidden_path = Keyword.get(opts, :forbidden_path, "/organizations")
    forbidden_message = Keyword.get(opts, :forbidden_message, "You don't have permission.")

    case Accounts.get_org_by_slug(slug) do
      nil ->
        halt(socket, "Organization not found.", "/organizations")

      org ->
        if Mode.current() == :local do
          {:ok, socket, org, nil}
        else
          user = socket.assigns[:current_user]

          cond do
            is_nil(user) ->
              halt(socket, "Sign in to view this organization.", "/auth/login")

            true ->
              case Accounts.get_active_membership(user.id, org.id) do
                nil ->
                  halt(socket, "You're not a member of that organization.", "/organizations")

                membership ->
                  if is_nil(role) or Accounts.role_at_least?(membership.role, role) do
                    {:ok, socket, org, membership}
                  else
                    halt(socket, forbidden_message, forbidden_path)
                  end
              end
          end
        end
    end
  end

  @doc """
  Authorize `/:org_slug/workspaces/:ws_slug` routes (and nested children).

  Same chain as `authorize_org/4` plus workspace existence and
  workspace-belongs-to-org. `role` is nil (any active member) or a minimum
  role such as `"admin"`.
  """
  @spec authorize_workspace(map(), String.t(), String.t(), role(), keyword()) ::
          {:ok, map(), map(), Workspace.t(), map() | nil} | {:halt, map()}
  def authorize_workspace(socket, org_slug, ws_slug, role \\ nil, opts \\ []) do
    role_message =
      Keyword.get(opts, :role_message, "Admin or owner role required.")

    with {:ok, socket, org, membership} <-
           authorize_org(socket, org_slug, nil, opts),
         %Workspace{} = workspace <-
           Mission.get_workspace_by_slug(ws_slug) |> Repo.preload(:org),
         :ok <- check_workspace_org(workspace, org) do
      if Mode.current() == :local do
        {:ok, socket, org, workspace, nil}
      else
        cond do
          is_nil(membership) ->
            halt(socket, "Workspace belongs to a different organization.", "/organizations")

          is_nil(role) ->
            {:ok, socket, org, workspace, membership}

          Accounts.role_at_least?(membership.role, role) ->
            {:ok, socket, org, workspace, membership}

          true ->
            halt(socket, role_message, "/organizations")
        end
      end
    else
      nil -> halt(socket, "Workspace not found.", "/organizations")
      {:error, message} -> halt(socket, message, "/organizations")
      {:halt, _} = halted -> halted
    end
  end

  defp check_workspace_org(%Workspace{org_id: nil}, _org),
    do: {:error, "Workspace is not bound to an org."}

  defp check_workspace_org(%Workspace{org_id: ws_org}, %{id: org_id})
       when is_integer(ws_org) and ws_org == org_id,
       do: :ok

  defp check_workspace_org(_, _),
    do: {:error, "Workspace does not belong to this organization."}

  defp halt(socket, message, path) do
    {:halt, socket |> put_flash(:error, message) |> push_navigate(to: path)}
  end
end
