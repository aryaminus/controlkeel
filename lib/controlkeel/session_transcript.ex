defmodule ControlKeel.SessionTranscript do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ControlKeel.Mission.SessionEvent
  alias ControlKeel.Repo

  @recent_limit 10
  @summary_max 280
  @body_max 2_048
  @payload_string_max 4_096
  @max_busy_retries 5

  def record(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)
    do_record(attrs, 1)
  end

  def recent_events(session_id, opts \\ []) when is_integer(session_id) do
    limit = Keyword.get(opts, :limit, @recent_limit)

    SessionEvent
    |> where([event], event.session_id == ^session_id)
    |> order_by([event], desc: event.inserted_at, desc: event.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&event_entry/1)
  end

  def summary(session_id) when is_integer(session_id) do
    SessionEvent
    |> where([event], event.session_id == ^session_id)
    |> order_by([event], desc: event.inserted_at, desc: event.id)
    |> Repo.all()
    |> build_summary()
  end

  defp build_summary(events) do
    families =
      events
      |> Enum.group_by(&event_family(&1.event_type))
      |> Enum.map(fn {family, family_events} ->
        latest =
          Enum.max_by(family_events, &DateTime.to_unix(&1.inserted_at || DateTime.utc_now()))

        %{
          "family" => family,
          "count" => length(family_events),
          "latest_at" => latest.inserted_at
        }
      end)
      |> Enum.sort_by(&{&1["family"] == "other", &1["family"]})

    %{
      "total_events" => length(events),
      "families" => families
    }
  end

  defp event_entry(%SessionEvent{} = event) do
    %{
      "id" => event.id,
      "event_type" => event.event_type,
      "family" => event_family(event.event_type),
      "actor" => event.actor,
      "summary" => event.summary,
      "body" => event.body,
      "payload" => event.payload || %{},
      "metadata" => event.metadata || %{},
      "task_id" => event.task_id,
      "inserted_at" => event.inserted_at
    }
  end

  defp normalize_attrs(attrs) do
    attrs = stringify_keys(attrs)

    %{
      event_type: attrs["event_type"] || "other.recorded",
      actor: attrs["actor"] || "system",
      summary: clip_text(attrs["summary"] || "Recorded event", @summary_max),
      body: clip_text(attrs["body"] || "", @body_max),
      payload: clip_payload(attrs["payload"] || %{}),
      metadata: clip_payload(attrs["metadata"] || %{}),
      session_id: attrs["session_id"],
      task_id: attrs["task_id"]
    }
  end

  defp clip_payload(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp clip_payload(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp clip_payload(%Date{} = value), do: Date.to_iso8601(value)
  defp clip_payload(%Time{} = value), do: Time.to_iso8601(value)

  defp clip_payload(%_{} = value), do: inspect(value)

  defp clip_payload(value) when is_map(value) do
    Enum.into(value, %{}, fn {key, item} ->
      {to_string(key), clip_payload(item)}
    end)
  end

  defp clip_payload(value) when is_list(value), do: Enum.map(value, &clip_payload/1)
  defp clip_payload(value) when is_binary(value), do: clip_text(value, @payload_string_max)
  defp clip_payload(value), do: value

  defp clip_text(value, max_length) when is_binary(value) do
    if String.length(value) <= max_length do
      value
    else
      String.slice(value, 0, max_length - 1) <> "…"
    end
  end

  defp clip_text(value, max_length), do: value |> to_string() |> clip_text(max_length)

  defp do_record(attrs, attempt) do
    %SessionEvent{}
    |> SessionEvent.changeset(attrs)
    |> Repo.insert()
  rescue
    error ->
      if busy_error?(error) and attempt < @max_busy_retries do
        Process.sleep(attempt * 20)
        do_record(attrs, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp busy_error?(error) do
    error
    |> Exception.message()
    |> String.contains?("Database busy")
  end

  defp event_family(event_type) when is_binary(event_type) do
    case String.split(event_type, ".", parts: 2) do
      [family, _rest] -> family
      [family] -> family
      _ -> "other"
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end
end
