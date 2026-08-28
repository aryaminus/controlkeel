defmodule ControlKeel.Mission.ReviewOps do
  @moduledoc """
  Review lifecycle operations extracted from the `Mission` context.

  Owns read paths, gate status, decision hygiene, and submission/response.
  `Mission` delegates to this module so existing `Mission.*` call sites keep
  working. Shared helpers (get_task, get_session, etc.) stay in `Mission`
  and are called back via `Mission.*`.
  """

  import Ecto.Query, only: [where: 3, order_by: 3, limit: 2]

  alias ControlKeel.Mission
  alias ControlKeel.Mission.Review
  alias ControlKeel.Mission.Task
  alias ControlKeel.Repo
  alias ControlKeel.Repo.Retry, as: RepoRetry
  alias ControlKeel.Accounts
  alias Ecto.Multi

  def get_review(id), do: Repo.get(Review, id)
  def get_review!(id), do: Repo.get!(Review, id)

  def get_review_with_context(id) do
    Review
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      review ->
        Repo.preload(review, [:previous_review, :revisions, task: [], session: :workspace])
    end
  end

  def list_reviews_for_session(session_id) when is_integer(session_id) do
    Review
    |> where([review], review.session_id == ^session_id)
    |> order_by([review], desc: review.inserted_at, desc: review.id)
    |> Repo.all()
    |> Repo.preload([:previous_review, task: []])
  end

  def latest_review_for_task(task_id, review_type \\ nil)

  def latest_review_for_task(task_id, nil) when is_integer(task_id) do
    Review
    |> where([review], review.task_id == ^task_id)
    |> order_by([review], desc: review.inserted_at, desc: review.id)
    |> limit(1)
    |> Repo.one()
  end

  def latest_review_for_task(task_id, review_type)
      when is_integer(task_id) and is_binary(review_type) do
    Review
    |> where([review], review.task_id == ^task_id and review.review_type == ^review_type)
    |> order_by([review], desc: review.inserted_at, desc: review.id)
    |> limit(1)
    |> Repo.one()
  end

  def review_gate_status(%Task{} = task) do
    gate = get_in(task.metadata || %{}, ["review_gate"]) || %{}

    %{
      "phase" => gate["phase"] || "execution",
      "execution_ready" => Map.get(gate, "execution_ready", true),
      "decision_gate" => gate["decision_gate"],
      "governed_manifest" => gate["governed_manifest"],
      "latest_review_id" => gate["latest_review_id"],
      "latest_review_status" => gate["latest_review_status"],
      "latest_review_type" => gate["latest_review_type"],
      "latest_plan_phase" => gate["latest_plan_phase"],
      "plan_quality_status" => gate["plan_quality_status"],
      "plan_quality_score" => gate["plan_quality_score"],
      "planning_depth" => gate["planning_depth"],
      "grill_questions" => gate["grill_questions"] || [],
      "decision_prompts" => gate["decision_prompts"] || [],
      "diagnostic_findings" => decision_hygiene_findings(task)
    }
  end

  def decision_hygiene_findings(%Task{} = task, attrs \\ %{}) do
    gate = get_in(task.metadata || %{}, ["review_gate"]) || %{}
    plan_quality = gate["plan_quality"] || %{}
    plan_refinement = gate["plan_refinement"] || %{}

    depth = plan_refinement["depth"] || gate["planning_depth"] || 1
    scope_high = plan_quality["scope_high"]
    missing = plan_quality["missing"] || []
    validation_plan = plan_refinement["validation_plan"] || []

    sunk_cost =
      if depth >= 3 do
        [
          %{
            "category" => "decision-hygiene",
            "severity" => "medium",
            "rule_id" => "planning.sunk_cost_signal",
            "title" => "Sunk-cost risk: plan refinement depth is #{depth}",
            "plain_message" =>
              "This plan has been refined #{depth} times. Consider whether continued refinement is justified by new evidence, or whether the current plan should be approved, narrowed, or abandoned.",
            "metadata" =>
              Map.merge(attrs, %{
                "diagnostic_source" => "mission_decision_hygiene",
                "planning_depth" => depth,
                "task_id" => task.id
              })
          }
        ]
      else
        []
      end

    scope_without_evidence =
      if scope_high == true and "validation_plan" in missing do
        [
          %{
            "category" => "decision-hygiene",
            "severity" => "high",
            "rule_id" => "planning.scope_without_evidence",
            "title" => "High-scope plan missing validation evidence",
            "plain_message" =>
              "The plan has high scope but no validation plan. Large changes without concrete verification steps are the strongest predictor of post-merge failures.",
            "metadata" =>
              Map.merge(attrs, %{
                "diagnostic_source" => "mission_decision_hygiene",
                "scope_high" => true,
                "missing_fields" => missing,
                "task_id" => task.id
              })
          }
        ]
      else
        []
      end

    weak_verification =
      if depth >= 2 and validation_plan == [] and plan_quality["execution_ready_phase"] == true do
        [
          %{
            "category" => "decision-hygiene",
            "severity" => "medium",
            "rule_id" => "review.weak_verification_confidence",
            "title" => "Execution-ready plan lacks verification steps",
            "plain_message" =>
              "The plan has reached execution-ready phase at depth #{depth} but still has no validation plan. Approval without verification evidence weakens the review gate.",
            "metadata" =>
              Map.merge(attrs, %{
                "diagnostic_source" => "mission_decision_hygiene",
                "planning_depth" => depth,
                "execution_ready_phase" => true,
                "task_id" => task.id
              })
          }
        ]
      else
        []
      end

    sunk_cost ++ scope_without_evidence ++ weak_verification
  end

  def execution_ready?(%Task{} = task) do
    review_gate_status(task)["execution_ready"] != false
  end

  def execution_ready?(task_id) when is_integer(task_id) do
    case Mission.get_task(task_id) do
      nil -> false
      task -> execution_ready?(task)
    end
  end

  def submit_review(attrs) do
    with {:ok, normalized} <- Mission.normalize_review_submission(attrs) do
      Multi.new()
      |> Mission.maybe_supersede_pending_reviews(normalized)
      |> Multi.insert(:review, Review.changeset(%Review{}, normalized.attrs))
      |> Mission.maybe_track_task_review_gate(normalized)
      |> Mission.maybe_track_review_runtime_context(normalized)
      |> RepoRetry.transaction_with_busy_retry()
      |> case do
        {:ok, %{review: review}} ->
          review = get_review_with_context(review.id)
          Mission.record_review_memory(:submitted, review)
          {:ok, review}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  def respond_review(review_or_id, attrs)

  def respond_review(review_id, attrs) when is_integer(review_id) do
    case get_review(review_id) do
      nil -> {:error, :not_found}
      review -> respond_review(review, attrs)
    end
  end

  def respond_review(%Review{} = review, attrs) do
    with {:ok, normalized} <- Mission.normalize_review_response(attrs) do
      review_attrs = Mission.merge_review_response_attrs(review, normalized.review_attrs)

      Multi.new()
      |> Multi.update(:review, Review.changeset(review, review_attrs))
      |> Multi.run(:review_audit_event, fn _repo, %{review: updated} ->
        Accounts.record_review_decision_event(updated, %{
          event_type: normalized.decision,
          actor_source: Map.get(review_attrs, "reviewed_by"),
          actor_identifier: Map.get(review_attrs, "reviewed_by"),
          note: Map.get(review_attrs, "feedback_notes"),
          recorded_at: Map.get(review_attrs, "responded_at")
        })
      end)
      |> Mission.maybe_apply_review_response_gate(review, normalized)
      |> RepoRetry.transaction_with_busy_retry()
      |> case do
        {:ok, %{review: updated}} ->
          updated = get_review_with_context(updated.id)
          action = if updated.status == "approved", do: :approved, else: :denied
          Mission.record_review_memory(action, updated)
          Mission.maybe_record_prompt_outcome(updated)
          {:ok, updated}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end
end
