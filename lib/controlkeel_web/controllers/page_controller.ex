defmodule ControlKeelWeb.PageController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Analytics
  alias ControlKeel.Mission

  def home(conn, _params) do
    render(conn, :home,
      recent_sessions: Mission.list_recent_sessions(),
      ship_summary: Analytics.funnel_summary()
    )
  end

  def getting_started(conn, _params) do
    render(conn, :getting_started)
  end
end
