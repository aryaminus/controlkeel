defmodule ControlKeelWeb.DocsController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Skills

  plug :put_layout, html: {ControlKeelWeb.Layouts, :docs}

  def index(conn, _params) do
    render(conn, :index)
  end

  def getting_started(conn, _params) do
    render(conn, :getting_started, install_channels: Skills.install_channels())
  end

  def agents(conn, _params) do
    render(conn, :agents, agent_integrations: Skills.agent_integrations())
  end

  def governance(conn, _params) do
    render(conn, :governance)
  end

  def observability(conn, _params) do
    render(conn, :observability)
  end

  # Legacy guide URL (removed when the guide moved under /docs).
  def legacy_redirect(conn, _params) do
    redirect(conn, to: ~p"/docs/getting-started")
  end
end
