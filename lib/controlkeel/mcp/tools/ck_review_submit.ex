defmodule ControlKeel.MCP.Tools.CkReviewSubmit do
  @moduledoc false

  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    attrs =
      Map.take(
        arguments,
        ~w(session_id task_id title review_type submission_body annotations feedback_notes submitted_by metadata previous_review_id plan_phase research_summary codebase_findings prior_art_summary options_considered selected_option rejected_options implementation_steps validation_plan code_snippets scope_estimate)
      )

    case Mission.submit_review(attrs) do
      {:ok, review} ->
        plan_refinement = get_in(review.metadata || %{}, ["plan_refinement"]) || %{}

        {:ok,
         %{
           "review_id" => review.id,
           "title" => review.title,
           "review_type" => review.review_type,
           "status" => review.status,
           "session_id" => review.session_id,
           "task_id" => review.task_id,
           "plan_phase" => plan_refinement["phase"],
           "plan_quality" => plan_refinement["quality"],
           "grill_questions" => get_in(plan_refinement, ["quality", "grill_questions"]) || [],
           "browser_url" => ControlKeelWeb.Endpoint.url() <> "/reviews/#{review.id}"
         }}

      {:error, {:invalid_arguments, reason}} ->
        {:error, {:invalid_arguments, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
