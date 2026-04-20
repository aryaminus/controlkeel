defmodule ControlKeel.OrchestrationEvents do
  @moduledoc false

  # Typed CK orchestration event namespace for provider-neutral runtime surfaces.
  # These event names and payload shapes are designed to be emitted into
  # orchestration streams (e.g. t3code's orchestration.domainEvent channel)
  # for first-class UI visibility of CK governance state.

  @namespace "ck"

  # Event names
  def finding_opened, do: "#{@namespace}.finding.opened"
  def review_pending, do: "#{@namespace}.review.pending"
  def review_approved, do: "#{@namespace}.review.approved"
  def review_denied, do: "#{@namespace}.review.denied"
  def budget_updated, do: "#{@namespace}.budget.updated"
  def proof_ready, do: "#{@namespace}.proof.ready"
  def turn_opened, do: "#{@namespace}.turn.opened"
  def turn_closed, do: "#{@namespace}.turn.closed"
  def policy_check, do: "#{@namespace}.policy.check"

  # Payload builders

  def finding_payload(finding) do
    %{
      "event" => finding_opened(),
      "severity" => Map.get(finding, :severity) || Map.get(finding, "severity"),
      "rule_id" => Map.get(finding, :rule_id) || Map.get(finding, "rule_id"),
      "category" => Map.get(finding, :category) || Map.get(finding, "category"),
      "plain_message" => Map.get(finding, :plain_message) || Map.get(finding, "plain_message"),
      "decision" => Map.get(finding, :decision) || Map.get(finding, "decision"),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def review_payload(review, status) do
    %{
      "event" => review_event_name(status),
      "review_id" => Map.get(review, :id) || Map.get(review, "id"),
      "title" => Map.get(review, :title) || Map.get(review, "title"),
      "status" => to_string(status),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def budget_payload(budget_state) do
    %{
      "event" => budget_updated(),
      "session_budget_cents" =>
        Map.get(budget_state, :session_budget_cents) ||
          Map.get(budget_state, "session_budget_cents"),
      "spent_cents" =>
        Map.get(budget_state, :spent_cents) || Map.get(budget_state, "spent_cents"),
      "remaining_session_cents" =>
        Map.get(budget_state, :remaining_session_cents) ||
          Map.get(budget_state, "remaining_session_cents"),
      "remaining_daily_cents" =>
        Map.get(budget_state, :remaining_daily_cents) ||
          Map.get(budget_state, "remaining_daily_cents"),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def proof_payload(proof) do
    %{
      "event" => proof_ready(),
      "proof_type" => Map.get(proof, :type) || Map.get(proof, "type"),
      "reference" => Map.get(proof, :reference) || Map.get(proof, "reference"),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def turn_payload(:open, thread_id, turn_id) do
    %{
      "event" => turn_opened(),
      "thread_id" => thread_id,
      "turn_id" => turn_id,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def turn_payload(:close, thread_id, turn_id) do
    %{
      "event" => turn_closed(),
      "thread_id" => thread_id,
      "turn_id" => turn_id,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def policy_check_payload(request_id, decision, opts \\ []) do
    %{
      "event" => policy_check(),
      "request_id" => request_id,
      "decision" => to_string(decision),
      "rule_ids" => Keyword.get(opts, :rule_ids, []),
      "reason" => Keyword.get(opts, :reason),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def all_event_names do
    [
      finding_opened(),
      review_pending(),
      review_approved(),
      review_denied(),
      budget_updated(),
      proof_ready(),
      turn_opened(),
      turn_closed(),
      policy_check()
    ]
  end

  defp review_event_name(:pending), do: review_pending()
  defp review_event_name("pending"), do: review_pending()
  defp review_event_name(:approved), do: review_approved()
  defp review_event_name("approved"), do: review_approved()
  defp review_event_name(:denied), do: review_denied()
  defp review_event_name("denied"), do: review_denied()
  defp review_event_name(other), do: "#{@namespace}.review.#{other}"
end
