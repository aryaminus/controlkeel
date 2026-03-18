defmodule ControlKeelWeb.LaunchController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Mission

  def new(conn, params) do
    render_form(conn, Mission.change_launch(params))
  end

  def create(conn, %{"launch" => launch_params}) do
    case Mission.create_launch(launch_params) do
      {:ok, session} ->
        conn
        |> put_flash(:info, "Mission compiled. ControlKeel generated the first execution path.")
        |> redirect(to: ~p"/missions/#{session.id}")

      {:error, _scope, changeset} ->
        conn
        |> put_flash(
          :error,
          "ControlKeel needs a bit more signal before it can create the mission."
        )
        |> render_form(changeset)
    end
  end

  defp render_form(conn, changeset) do
    industries = Mission.industries() |> Enum.sort_by(fn {_id, profile} -> profile.label end)
    agents = Mission.agent_labels() |> Enum.sort_by(fn {_id, label} -> label end)

    render(conn, :new,
      form: Phoenix.Component.to_form(changeset, as: :launch),
      industries: industries,
      agents: agents
    )
  end
end
