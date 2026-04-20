defmodule ControlKeel.Governance.ThreadState do
  @moduledoc false

  # Single endpoint that returns findings+reviews+budget for a given thread/session.
  # Implements the listState portion of the CkT3Adapter interface (§2 of spec).

  alias ControlKeel.Budget.Telemetry
  alias ControlKeel.Mission

  @doc """
  List consolidated governance state for a session/thread.

  Returns:
    - findings: list of finding summaries
    - reviews: list of review summaries
    - budget: budget summary with thresholds
  """
  def list(session_id, opts \\ []) do
    thread_id = Keyword.get(opts, :thread_id)

    %{
      findings: list_findings(session_id, thread_id),
      reviews: list_reviews(session_id, thread_id),
      budget: budget_summary(session_id)
    }
  end

  @doc """
  List finding summaries for a session.
  """
  def list_findings(session_id, _thread_id) do
    session = Mission.get_session_context(session_id)

    case session do
      nil ->
        []

      session ->
        (session.findings || [])
        |> Enum.map(fn
          %{} = finding ->
            %{
              id: Map.get(finding, :id) || Map.get(finding, "id"),
              severity: Map.get(finding, :severity) || Map.get(finding, "severity"),
              rule_id: Map.get(finding, :rule_id) || Map.get(finding, "rule_id"),
              category: Map.get(finding, :category) || Map.get(finding, "category"),
              decision: Map.get(finding, :status) || Map.get(finding, "status"),
              message: Map.get(finding, :plain_message) || Map.get(finding, "plain_message")
            }

          _ ->
            %{}
        end)
    end
  end

  @doc """
  List review summaries for a session.
  """
  def list_reviews(session_id, _thread_id) do
    reviews = Mission.list_reviews_for_session(session_id)

    Enum.map(reviews, fn review ->
      %{
        id: review.id,
        title: review.title,
        status: review.status,
        review_type: review.review_type,
        submitted_by: review.submitted_by,
        inserted_at: review.inserted_at
      }
    end)
  end

  @doc """
  Get budget summary for a session.
  """
  def budget_summary(session_id) do
    session = Mission.get_session(session_id)

    case session do
      nil ->
        empty_budget()

      session ->
        budget_cents = Map.get(session, :budget_cents) || 0
        spent_cents = Map.get(session, :spent_cents) || 0
        daily_cents = Map.get(session, :daily_budget_cents) || 0

        # Use Telemetry.snapshot for a consistent payload
        Telemetry.snapshot(session_id, budget_cents, spent_cents, daily_budget_cents: daily_cents)
    end
  end

  defp empty_budget do
    %{
      "event" => "ck.budget.updated",
      "session_budget_cents" => 0,
      "spent_cents" => 0,
      "remaining_session_cents" => 0,
      "remaining_daily_cents" => 0
    }
  end
end
