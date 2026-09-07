defmodule ControlKeel.Governance.SessionDigest do
  @moduledoc """
  Generates condensed, human-scannable digests of what happened in a session.

  A forward-deployed engineer managing multiple agents needs an "inbox that
  summarizes what happened" — not a raw event stream.

  Three digest types:
    - session: full session summary
    - daily: last 24 hours
    - shift_change: since the last digest was generated
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Repo
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Finding, SessionDigest, Task, Review}
  alias ControlKeel.Governance.TechDebtDetector

  @doc "Generate a new digest for a session."
  def generate(session_id, opts \\ []) do
    digest_type = Keyword.get(opts, :digest_type, "session")
    session = Mission.get_session!(session_id)

    {period_start, period_end} = period_bounds(session, digest_type, opts)

    tasks = load_tasks(session_id, period_start, period_end)
    findings = load_findings(session_id, period_start, period_end)
    reviews = load_reviews(session_id, period_start, period_end)
    tech_debt_signals = TechDebtDetector.detect_for_session(session_id, opts)

    top_rule_ids = count_by_field(findings, :rule_id)
    top_categories = count_by_field(findings, :category)

    highlights = build_highlights(tasks, findings, reviews, session, tech_debt_signals)

    needs_attention =
      Enum.count(findings, &(&1.status == "blocked")) > 0 or
        Enum.count(reviews, &(&1.status == "pending")) > 0 or
        session.spent_cents > div(session.budget_cents, 5) * 4 or
        tech_debt_signals != []

    avg_task_duration_seconds = avg_task_duration(tasks)
    tasks_per_hour = tasks_per_hour(tasks, period_start, period_end)

    attrs = %{
      session_id: session_id,
      digest_type: digest_type,
      period_start: period_start,
      period_end: period_end,
      tasks_completed: Enum.count(tasks, &(&1.status == "completed")),
      tasks_failed: Enum.count(tasks, &(&1.status == "failed")),
      findings_raised: length(findings),
      findings_blocked: Enum.count(findings, &(&1.status == "blocked")),
      reviews_pending: Enum.count(reviews, &(&1.status == "pending")),
      reviews_approved: Enum.count(reviews, &(&1.status == "approved")),
      budget_spent_cents: session.spent_cents,
      budget_remaining_cents: max(session.budget_cents - session.spent_cents, 0),
      top_rule_ids: top_rule_ids,
      top_categories: top_categories,
      highlights: highlights,
      needs_attention: needs_attention,
      generated_at: DateTime.utc_now(),
      metadata: %{
        "avg_task_duration_seconds" => avg_task_duration_seconds,
        "tasks_per_hour" => tasks_per_hour,
        "tech_debt_signals" => tech_debt_signals
      }
    }

    %SessionDigest{}
    |> SessionDigest.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get the latest digest for a session."
  def latest(session_id) do
    SessionDigest
    |> where([d], d.session_id == ^session_id)
    |> order_by(desc: :id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "List digests for a session, newest first."
  def list(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    SessionDigest
    |> where([d], d.session_id == ^session_id)
    |> order_by(desc: :generated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp period_bounds(session, "session", _opts) do
    {session.inserted_at, DateTime.utc_now()}
  end

  defp period_bounds(_session, "daily", _opts) do
    {DateTime.add(DateTime.utc_now(), -24, :hour), DateTime.utc_now()}
  end

  defp period_bounds(_session, "shift_change", opts) do
    last_digest = Keyword.get(opts, :last_digest)

    start_time =
      if last_digest do
        last_digest.generated_at
      else
        DateTime.add(DateTime.utc_now(), -8, :hour)
      end

    {start_time, DateTime.utc_now()}
  end

  defp load_tasks(session_id, period_start, period_end) do
    Task
    |> where([t], t.session_id == ^session_id)
    |> where([t], t.inserted_at >= ^period_start and t.inserted_at <= ^period_end)
    |> Repo.all()
  end

  defp load_findings(session_id, period_start, period_end) do
    Finding
    |> where([f], f.session_id == ^session_id)
    |> where([f], f.inserted_at >= ^period_start and f.inserted_at <= ^period_end)
    |> Repo.all()
  end

  defp load_reviews(session_id, period_start, period_end) do
    Review
    |> where([r], r.session_id == ^session_id)
    |> where([r], r.inserted_at >= ^period_start and r.inserted_at <= ^period_end)
    |> Repo.all()
  end

  defp count_by_field(records, field) do
    # ⚡ Bolt: Use Enum.frequencies_by/2 to avoid intermediate list allocations
    records
    |> Enum.frequencies_by(&Map.get(&1, field))
    |> Enum.sort_by(fn {_k, v} -> v end, :desc)
    |> Enum.take(5)
    |> Map.new()
  end

  defp build_highlights(tasks, findings, reviews, session, tech_debt_signals) do
    highlights = []

    highlights =
      tech_debt_signals
      |> Enum.take(3)
      |> Enum.reduce(highlights, fn signal, acc ->
        [%{"type" => "tech_debt", "summary" => signal.message} | acc]
      end)

    highlights =
      if session.spent_cents > div(session.budget_cents, 5) * 4 do
        [%{"type" => "budget_threshold", "summary" => "Budget >80% consumed"} | highlights]
      else
        highlights
      end

    highlights =
      findings
      |> Enum.filter(&(&1.severity in ["critical", "high"]))
      |> Enum.take(3)
      |> Enum.reduce(highlights, fn f, acc ->
        [%{"type" => "high_severity_finding", "summary" => f.plain_message} | acc]
      end)

    highlights =
      reviews
      |> Enum.filter(&(&1.status == "pending"))
      |> Enum.take(2)
      |> Enum.reduce(highlights, fn r, acc ->
        [%{"type" => "pending_review", "summary" => "Review pending: #{r.title}"} | acc]
      end)

    highlights =
      tasks
      |> Enum.filter(&(&1.status == "completed"))
      |> Enum.take(3)
      |> Enum.reduce(highlights, fn t, acc ->
        [%{"type" => "task_completed", "summary" => "Completed: #{t.title}"} | acc]
      end)

    %{"items" => Enum.take(Enum.reverse(highlights), 10)}
  end

  defp avg_task_duration(tasks) do
    durations =
      tasks
      |> Enum.filter(&(&1.status == "completed"))
      |> Enum.map(fn t ->
        if t.updated_at && t.inserted_at do
          DateTime.diff(t.updated_at, t.inserted_at, :second)
        end
      end)
      |> Enum.reject(&is_nil/1)

    if durations == [] do
      nil
    else
      Float.round(Enum.sum(durations) / length(durations), 1)
    end
  end

  defp tasks_per_hour(tasks, period_start, period_end) do
    completed = Enum.count(tasks, &(&1.status == "completed"))
    period_seconds = DateTime.diff(period_end, period_start, :second)

    if period_seconds <= 0 do
      0.0
    else
      Float.round(completed / (period_seconds / 3600.0), 2)
    end
  end
end
