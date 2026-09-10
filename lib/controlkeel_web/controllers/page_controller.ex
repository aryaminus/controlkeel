defmodule ControlKeelWeb.PageController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Accounts
  alias ControlKeel.Bootstrap.LocalDefaults
  alias ControlKeel.Mission
  alias ControlKeel.Runtime.Mode
  alias ControlKeel.Skills

  # Public marketing pages render inside the `:public` framework layout
  # (ControlKeelWeb.Layouts). The layout reads @current_user/@flash directly,
  # so nothing needs to be forwarded from the templates.
  plug :put_layout, html: {ControlKeelWeb.Layouts, :public}

  def home(conn, _params) do
    cond do
      # Local mode has no marketing surface — `/` goes straight to the
      # default org. ensure/0 is idempotent (find-or-create), so a fresh
      # local install provisions the org on first visit.
      Mode.current() == :local ->
        _ = LocalDefaults.ensure()
        redirect(conn, to: ~p"/#{LocalDefaults.default_org_slug()}")

      # Signed-in cloud/self_hosted users get their org → workspace →
      # session selector tree instead of the marketing landing.
      user = conn.assigns[:current_user] ->
        render(conn, :selector_tree, tree: selector_tree(user))

      true ->
        render(conn, :home)
    end
  end

  defp selector_tree(user) do
    orgs =
      user.id
      |> Accounts.list_orgs_for_user()
      |> Enum.map(& &1.org)
      |> Enum.sort_by(& &1.name)

    workspaces =
      orgs
      |> Enum.map(& &1.id)
      |> Mission.list_workspaces_for_orgs()

    sessions_by_workspace =
      workspaces
      |> Enum.map(& &1.id)
      |> Mission.list_sessions_for_workspaces()
      |> Enum.group_by(& &1.workspace_id)

    workspaces_by_org = Enum.group_by(workspaces, & &1.org_id)

    Enum.map(orgs, fn org ->
      workspaces =
        Enum.map(workspaces_by_org[org.id] || [], fn workspace ->
          %{workspace: workspace, sessions: sessions_by_workspace[workspace.id] || []}
        end)

      %{org: org, workspaces: workspaces}
    end)
  end

  def getting_started(conn, _params) do
    render(conn, :getting_started,
      install_channels: Skills.install_channels(),
      agent_integrations: Skills.agent_integrations()
    )
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def contact(conn, _params) do
    render(conn, :contact)
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def developers(conn, _params) do
    render(conn, :developers)
  end
end
