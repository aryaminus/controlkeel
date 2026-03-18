defmodule ControlKeel.Analytics.TelemetryHandler do
  @moduledoc false

  use GenServer

  alias ControlKeel.Analytics

  @handler_id "controlkeel-analytics-telemetry-handler"
  @events [
    [:controlkeel, :local_project, :initialized],
    [:controlkeel, :claude, :attach, :succeeded],
    [:controlkeel, :intent, :interview, :started],
    [:controlkeel, :intent, :interview, :step_completed],
    [:controlkeel, :intent, :mission, :created],
    [:controlkeel, :proxy, :decision],
    [:controlkeel, :finding, :approved],
    [:controlkeel, :finding, :rejected],
    [:controlkeel, :autofix, :viewed],
    [:controlkeel, :autofix, :copied],
    [:controlkeel, :session, :first_finding_recorded]
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :telemetry.detach(@handler_id)

    :ok =
      :telemetry.attach_many(
        @handler_id,
        @events,
        &__MODULE__.handle_event/4,
        %{pid: self()}
      )

    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  @impl true
  def handle_info({:telemetry, event, measurements, metadata}, state) do
    maybe_record(event, measurements, metadata)

    {:noreply, state}
  end

  def handle_event(event, measurements, metadata, %{pid: pid}) do
    send(pid, {:telemetry, event, measurements, metadata})
  end

  defp analytics_payload([:controlkeel, :local_project, :initialized], measurements, metadata) do
    build_payload("project_initialized", "local_project", measurements, metadata)
  end

  defp analytics_payload([:controlkeel, :claude, :attach, :succeeded], measurements, metadata) do
    build_payload("agent_attached", "claude", measurements, metadata)
  end

  defp analytics_payload([:controlkeel, :intent, :interview, :started], measurements, metadata) do
    build_payload("intent_interview_started", "intent", measurements, metadata)
  end

  defp analytics_payload(
         [:controlkeel, :intent, :interview, :step_completed],
         measurements,
         metadata
       ) do
    build_payload("intent_interview_step_completed", "intent", measurements, metadata)
  end

  defp analytics_payload([:controlkeel, :intent, :mission, :created], measurements, metadata) do
    build_payload("mission_created", "intent", measurements, metadata)
  end

  defp analytics_payload([:controlkeel, :proxy, :decision], measurements, metadata) do
    build_payload("proxy_decision", "proxy", measurements, metadata)
  end

  defp analytics_payload([:controlkeel, :finding, :approved], measurements, metadata) do
    build_payload("finding_approved", "finding", measurements, metadata)
  end

  defp analytics_payload([:controlkeel, :finding, :rejected], measurements, metadata) do
    build_payload("finding_rejected", "finding", measurements, metadata)
  end

  defp analytics_payload([:controlkeel, :autofix, :viewed], measurements, metadata) do
    build_payload("autofix_viewed", "autofix", measurements, metadata)
  end

  defp analytics_payload([:controlkeel, :autofix, :copied], measurements, metadata) do
    build_payload("autofix_copied", "autofix", measurements, metadata)
  end

  defp analytics_payload(
         [:controlkeel, :session, :first_finding_recorded],
         measurements,
         metadata
       ) do
    build_payload("first_finding_recorded", "session", measurements, metadata)
  end

  defp analytics_payload(_event, _measurements, _metadata), do: nil

  defp maybe_record(event, measurements, metadata) do
    case analytics_payload(event, measurements, metadata) do
      nil ->
        :ok

      payload ->
        try do
          Analytics.record(payload)
        rescue
          _error -> :ok
        end
    end
  end

  defp build_payload(event, source, measurements, metadata) do
    metadata = normalize_metadata(metadata)

    %{
      event: event,
      source: source,
      session_id: metadata["session_id"],
      workspace_id: metadata["workspace_id"],
      project_root: metadata["project_root"],
      happened_at: DateTime.utc_now() |> DateTime.truncate(:second),
      metadata:
        metadata
        |> Map.put("measurements", normalize_metadata(measurements))
    }
  end

  defp normalize_metadata(metadata) when is_map(metadata) do
    Enum.into(metadata, %{}, fn
      {key, value} when is_map(value) -> {to_string(key), normalize_metadata(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp normalize_metadata(_value), do: %{}
end
