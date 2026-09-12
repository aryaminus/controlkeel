defmodule ControlKeel.MCP.Tools.CkReviewSubmit do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.MCP.Tools.ReviewHelpers

  def call(arguments) when is_map(arguments) do
    try do
      do_call(arguments)
    rescue
      e -> {:error, "Review submission failed: #{Exception.message(e)}"}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp do_call(arguments) do
    review_attrs =
      Map.take(
        arguments,
        ~w(session_id task_id title review_type submission_body annotations feedback_notes submitted_by metadata previous_review_id plan_phase hypothesis expected_signal research_summary codebase_findings prior_art_summary alignment_context consulted_roles options_considered selected_option rejected_options implementation_steps validation_plan code_snippets agent_spec_id task_spec_id agent_role task_scope out_of_scope business_rules domain_terms persona_or_actor_context allowed_actions prohibited_actions robustness_requirements linked_policy_packs linked_benchmark_suites promotion_gates allowed_semantic_changes forbidden_semantic_changes invariant_boundaries requires_reapproval_if harness_quality_checks scope_estimate project_root)
      )
      |> maybe_pin_project_root(arguments)

    auto_approve_requested = Map.get(arguments, "auto_approve", false)
    auto_approve_reason = Map.get(arguments, "auto_approve_reason", "")

    case Mission.submit_review(review_attrs) do
      {:ok, review} ->
        plan_refinement = get_in(review.metadata || %{}, ["plan_refinement"]) || %{}

        browser_url =
          try do
            ControlKeel.Mission.ReviewBridge.browser_url(review)
          rescue
            _ -> nil
          end

        quality = plan_refinement["quality"]
        quality_safe = if is_map(quality), do: quality, else: nil

        # Check if auto-approval is warranted
        {auto_approved, auto_approve_reason_final} =
          if auto_approve_requested do
            check_auto_approve(review, auto_approve_reason)
          else
            {false, nil}
          end

        # If auto-approved, record the decision immediately
        final_review =
          if auto_approved do
            case Mission.respond_review(review.id, %{
                   "decision" => "approved",
                   "reviewed_by" => "controlkeel:auto_approve",
                   "feedback_notes" => auto_approve_reason_final
                 }) do
              {:ok, approved_review} -> approved_review
              _ -> review
            end
          else
            review
          end

        {:ok,
         %{
           "review_id" => final_review.id,
           "title" => final_review.title,
           "review_type" => final_review.review_type,
           "status" => final_review.status,
           "session_id" => final_review.session_id,
           "task_id" => final_review.task_id,
           "plan_phase" => plan_refinement["phase"],
           "plan_refinement" => plan_refinement,
           "plan_quality" => quality_safe,
           "grill_questions" => get_in(plan_refinement, ["quality", "grill_questions"]) || [],
           "browser_url" => browser_url,
           "review_url" => browser_url,
           "approval_instructions" =>
             ReviewHelpers.approval_instructions(final_review, browser_url),
           "review_roles" =>
             ReviewHelpers.review_roles(final_review.review_type, plan_refinement),
           "auto_approved" => auto_approved,
           "auto_approve_reason" => auto_approve_reason_final
         }}

      {:error, {:invalid_arguments, reason}} ->
        {:error, {:invalid_arguments, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # An explicit project_root must win over the ambient
  # CONTROLKEEL_PROJECT_ROOT/File.cwd!() fallback so a host running one MCP
  # server across repos (e.g. an IDE-wide CONTROLKEEL_PROJECT_ROOT) can still
  # pin a submission to the intended project's governed session.
  defp maybe_pin_project_root(review_attrs, arguments) do
    case Map.get(arguments, "project_root") do
      root when is_binary(root) and root != "" ->
        review_attrs
        |> Map.put("project_root", root)
        |> put_in(
          [Access.key("metadata", %{}), Access.key("runtime_context", %{}), "project_root"],
          root
        )

      _ ->
        review_attrs
    end
  end

  # Checks if auto-approval is justified based on fast, local checks:
  # 1. No blocked findings on the review
  # 2. Low-risk work (small/medium scope, no security concerns, quality score >= 70)
  # 3. No requires_reapproval_if conditions triggered
  # Memory/policy/benchmark checks happen at the agent level before calling this tool.
  defp check_auto_approve(review, requested_reason) do
    checks = [
      check_no_blocked_findings(review),
      check_low_risk(review),
      check_no_reapproval_required(review)
    ]

    all_passed = Enum.all?(checks, fn {pass?, _reason} -> pass? end)
    reasons = Enum.map(checks, fn {_pass?, reason} -> reason end) |> Enum.reject(&is_nil/1)

    reason_text =
      if all_passed do
        base = "Auto-approved: #{Enum.join(reasons, "; ")}"
        if requested_reason != "", do: "#{base}. Agent: #{requested_reason}", else: base
      else
        nil
      end

    {all_passed, reason_text}
  end

  # Check if there are no blocked findings on this review
  defp check_no_blocked_findings(review) do
    findings = review.findings || []

    blocked =
      Enum.filter(findings, &(&1.severity in ["critical", "high"] and &1.status == "blocked"))

    if blocked == [] do
      {true, "no blocked findings"}
    else
      {false, nil}
    end
  end

  # Check if the work is low-risk based on review metadata
  defp check_low_risk(review) do
    metadata = review.metadata || %{}
    plan_refinement = metadata["plan_refinement"] || %{}
    quality = plan_refinement["quality"] || %{}

    # Low risk if: small scope, no security concerns, quality score > 70
    scope = plan_refinement["scope"] || "unknown"
    security_concerns = quality["security_concerns"] || []
    score = quality["score"] || 0

    low_scope = scope in ["small", "medium"]
    no_security = security_concerns == []
    good_quality = score >= 70

    if low_scope and no_security and good_quality do
      {true, "low risk (scope=#{scope}, score=#{score})"}
    else
      {false, nil}
    end
  end

  # Check if requires_reapproval_if conditions are met
  defp check_no_reapproval_required(review) do
    metadata = review.metadata || %{}
    plan_refinement = metadata["plan_refinement"] || %{}
    conditions = plan_refinement["requires_reapproval_if"] || []

    if conditions == [] do
      {true, "no reapproval conditions"}
    else
      # If there are reapproval conditions, we can't auto-approve
      {false, nil}
    end
  end
end
