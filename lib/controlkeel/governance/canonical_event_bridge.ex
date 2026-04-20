defmodule ControlKeel.Governance.CanonicalEventBridge do
  @moduledoc false

  # Ingests provider-neutral canonical runtime events (as emitted by t3code
  # and similar orchestration runtimes) and maps them to CK governance actions.
  #
  # Implements the ingestion side of the CkT3Adapter interface:
  #   ingestRuntimeEvent / ingestOrchestrationEvent
  #
  # Event mapping (§3A of spec):
  #   request.opened          -> ck.policy.check.request
  #   request.resolved        -> ck.policy.check.resolution
  #   user-input.requested    -> ck.hitl.input.requested
  #   turn.started            -> ck.turn.open
  #   turn.completed          -> ck.turn.close
  #   runtime.error           -> ck.incident.signal
  #   thread.token-usage.updated -> ck.budget.telemetry.input

  alias ControlKeel.Governance.{ApprovalAdapter, IdempotencyLedger}
  alias ControlKeel.Intent.RuntimePolicyProfile
  alias ControlKeel.OrchestrationEvents
  alias ControlKeel.SessionTranscript

  @canonical_event_mapping %{
    "request.opened" => "ck.policy.check.request",
    "request.resolved" => "ck.policy.check.resolution",
    "user-input.requested" => "ck.hitl.input.requested",
    "turn.started" => "ck.turn.open",
    "turn.completed" => "ck.turn.close",
    "runtime.error" => "ck.incident.signal",
    "thread.token-usage.updated" => "ck.budget.telemetry.input"
  }

  @doc """
  Ingest a canonical runtime event and produce the appropriate CK action.
  Returns {:ok, result} where result depends on event type, or
  {:ok, :duplicate} if the event was already processed.
  """
  def ingest(event, opts \\ []) do
    event_type = event["type"] || event["event_type"] || event[:type] || "unknown"
    session_id = event["session_id"] || event[:session_id]
    agent_id = Keyword.get(opts, :agent_id) || event["agent_id"] || event[:agent_id]

    dedupe_key = build_dedupe_key(event, session_id)

    case IdempotencyLedger.check_and_mark(dedupe_key) do
      :duplicate ->
        {:ok, :duplicate}

      :new ->
        result = dispatch_event(event_type, event, session_id, agent_id, opts)
        maybe_record_transcript(session_id, event_type, event, result)
        {:ok, result}
    end
  end

  @doc """
  Ingest a batch of canonical events in order.
  Returns list of {event_id, result} tuples.
  """
  def ingest_batch(events, opts \\ []) do
    Enum.map(events, fn event ->
      event_id = event["id"] || event["event_id"] || event[:id] || "unknown"
      {event_id, ingest(event, opts)}
    end)
  end

  @doc """
  Returns the canonical event mapping table.
  """
  def event_mapping, do: @canonical_event_mapping

  @doc """
  Maps a t3code event type to the CK normalized event name.
  """
  def normalize_event_type(t3code_type) do
    Map.get(@canonical_event_mapping, t3code_type, "ck.unmapped.#{t3code_type}")
  end

  # Dispatch by canonical event type

  defp dispatch_event("request.opened", event, _session_id, agent_id, opts) do
    tool = event["tool"] || event["requestType"] || "unknown"
    request_id = event["id"] || event["requestId"] || "unknown"
    policy_mode = Keyword.get(opts, :policy_mode)

    decision = ApprovalAdapter.evaluate(agent_id, %{"tool" => tool}, policy_mode: policy_mode)

    %{
      action: :evaluate_request,
      request_id: request_id,
      tool: tool,
      decision: decision,
      ck_event: normalize_event_type("request.opened")
    }
  end

  defp dispatch_event("request.resolved", event, _session_id, _agent_id, _opts) do
    request_id = event["id"] || event["requestId"] || "unknown"
    resolution = event["resolution"] || event["decision"] || "unknown"

    %{
      action: :resolution_recorded,
      request_id: request_id,
      resolution: resolution,
      ck_event: normalize_event_type("request.resolved")
    }
  end

  defp dispatch_event("user-input.requested", event, _session_id, _agent_id, _opts) do
    %{
      action: :awaiting_human_input,
      request_id: event["id"] || "unknown",
      prompt: event["prompt"] || event["message"],
      ck_event: normalize_event_type("user-input.requested")
    }
  end

  defp dispatch_event("turn.started", event, _session_id, _agent_id, _opts) do
    thread_id = event["threadId"] || event["thread_id"]
    turn_id = event["turnId"] || event["turn_id"]

    %{
      action: :turn_opened,
      thread_id: thread_id,
      turn_id: turn_id,
      ck_event: normalize_event_type("turn.started"),
      payload: OrchestrationEvents.turn_payload(:open, thread_id, turn_id)
    }
  end

  defp dispatch_event("turn.completed", event, _session_id, _agent_id, opts) do
    thread_id = event["threadId"] || event["thread_id"]
    turn_id = event["turnId"] || event["turn_id"]

    # Final validation pass at turn close
    profile_mode = Keyword.get(opts, :policy_mode, "full_access")
    profile = RuntimePolicyProfile.resolve(profile_mode)

    %{
      action: :turn_closed,
      thread_id: thread_id,
      turn_id: turn_id,
      post_turn_validation: profile["post_action"],
      ck_event: normalize_event_type("turn.completed"),
      payload: OrchestrationEvents.turn_payload(:close, thread_id, turn_id)
    }
  end

  defp dispatch_event("runtime.error", event, _session_id, _agent_id, _opts) do
    %{
      action: :incident_recorded,
      error: event["error"] || event["message"] || "unknown error",
      ck_event: normalize_event_type("runtime.error")
    }
  end

  defp dispatch_event("thread.token-usage.updated", event, _session_id, _agent_id, _opts) do
    %{
      action: :budget_telemetry_input,
      token_usage: event["tokenUsage"] || event["usage"] || %{},
      ck_event: normalize_event_type("thread.token-usage.updated")
    }
  end

  defp dispatch_event(unknown_type, _event, _session_id, _agent_id, _opts) do
    %{
      action: :unmapped,
      original_type: unknown_type,
      ck_event: normalize_event_type(unknown_type)
    }
  end

  defp build_dedupe_key(event, session_id) do
    %{
      session_id: session_id,
      thread_id: event["threadId"] || event["thread_id"],
      turn_id: event["turnId"] || event["turn_id"],
      event_id: event["id"] || event["event_id"] || event["sequence"],
      event_type: event["type"] || event["event_type"]
    }
  end

  defp maybe_record_transcript(nil, _event_type, _event, _result), do: :skip

  defp maybe_record_transcript(session_id, event_type, _event, result) do
    SessionTranscript.record(%{
      session_id: session_id,
      event_type: normalize_event_type(event_type),
      actor: "canonical_bridge",
      summary: "Ingested #{event_type}",
      body: summarize_event(event_type, result),
      payload: %{
        "original_type" => event_type,
        "action" => Map.get(result, :action) |> to_string()
      }
    })
  end

  defp summarize_event("request.opened", %{decision: d}), do: "Request evaluated: #{d.decision}"
  defp summarize_event("turn.started", _), do: "Turn opened"
  defp summarize_event("turn.completed", _), do: "Turn closed with post-turn validation"
  defp summarize_event(event_type, _), do: "Processed #{event_type}"
end
