defmodule ControlKeelWeb.SessionReleaseReadinessLive do
  @moduledoc """
  Release readiness gate for a session: verdict, proof, findings breakdown,
  blocking reasons, and smoke/provenance evidence form.
  Routed at `/sessions/:id/release-readiness`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Governance
  alias ControlKeel.Mission
  alias ControlKeelWeb.ReleaseReadiness

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns[:current_org_id]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(org_id) and not is_nil(session) ->
        if Accounts.session_accessible?(session, org_id) do
          if connected?(socket), do: schedule_refresh()
          {:ok, mount_session(socket, session)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Session not found.")
           |> push_navigate(to: ~p"/")}
        end

      session ->
        if connected?(socket), do: schedule_refresh()
        {:ok, mount_session(socket, session)}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil ->
        {:noreply, socket}

      session ->
        {:noreply, assign(socket, :session, session)}
    end
  end

  @impl true
  def handle_event("check_release_readiness", %{"release" => params}, socket) do
    form_params = Map.merge(release_form_defaults(), params)

    socket =
      socket
      |> assign(:release_form_params, form_params)
      |> assign_release_readiness(form_params, true)

    {:noreply,
     case socket.assigns.release_readiness do
       nil -> socket
       _readiness -> put_flash(socket, :info, "Release readiness checked.")
     end}
  end

  defp mount_session(socket, session) do
    form_params = release_form_defaults()

    socket
    |> assign(:page_title, "#{session.title} — Release readiness")
    |> assign(:session, session)
    |> assign(:release_form_params, form_params)
    |> assign_release_readiness(form_params, false)
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
  end

  defp release_form_defaults do
    %{
      "smoke_status" => "",
      "smoke_run" => "",
      "artifact_source" => "",
      "sha" => "",
      "provenance_verified" => "false"
    }
  end

  defp assign_release_readiness(socket, form_params, record_telemetry) do
    readiness =
      socket.assigns.session.id
      |> release_readiness_opts(form_params)
      |> Map.put(:record_telemetry, record_telemetry)
      |> Governance.release_readiness()
      |> case do
        {:ok, readiness} -> readiness
        {:error, _reason} -> nil
      end

    socket
    |> assign(:release_readiness, readiness)
    |> assign(:release_form, to_form(form_params, as: :release))
  rescue
    e ->
      require Logger
      Logger.warning("SessionReleaseReadinessLive release readiness rescued: #{inspect(e)}")

      socket
      |> assign(:release_readiness, nil)
      |> assign(:release_form, to_form(form_params, as: :release))
  end

  defp release_readiness_opts(session_id, params) do
    %{
      session_id: session_id,
      sha: blank_to_nil(params["sha"]),
      smoke: %{
        "status" => blank_to_nil(params["smoke_status"]),
        "run_id" => blank_to_nil(params["smoke_run"])
      },
      provenance: %{
        "verified" => params["provenance_verified"] in [true, "true"],
        "artifact_source" => blank_to_nil(params["artifact_source"])
      }
    }
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <ReleaseReadiness.release_readiness
      readiness={@release_readiness}
      form={@release_form}
      session_id={@session.id}
    />
    """
  end
end
