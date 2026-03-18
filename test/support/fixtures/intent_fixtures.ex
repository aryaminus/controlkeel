defmodule ControlKeel.IntentFixtures do
  @moduledoc false

  alias ControlKeel.Intent.ExecutionBrief

  def provider_brief_payload(overrides \\ %{}) do
    Map.merge(
      %{
        "project_name" => "Clinic Intake",
        "idea" => "Build a patient intake workflow for a small clinic",
        "objective" =>
          "Build a secure intake workflow for clinic staff with manageable releases.",
        "users" => "front desk staff and clinic admins",
        "occupation" => "Healthcare",
        "domain_pack" => "healthcare",
        "risk_tier" => "critical",
        "data_summary" => "Patient names, insurance notes, and scheduling details.",
        "compliance" => ["HIPAA", "HITECH", "OWASP Top 10"],
        "recommended_stack" => "Phoenix + Postgres + encrypted storage and audit logs",
        "acceptance_criteria" => [
          "Staff can submit and review intake records safely.",
          "The first release keeps PHI handling auditable and approval-gated."
        ],
        "open_questions" => ["Which EHR integration should the first release support?"],
        "estimated_tasks" => 4,
        "budget_note" => "$40/month to start",
        "next_step" =>
          "Lock the architecture, hosting boundary, and approval flow before code generation.",
        "launch_window" => "Internal pilot before broader rollout",
        "success_signal" =>
          "The clinic completes its first intake digitally without manual re-entry.",
        "key_features" => ["Intake form", "Review queue", "Audit logging"]
      },
      stringify_keys(overrides)
    )
  end

  def compiler_metadata(overrides \\ %{}) do
    Map.merge(
      %{
        "provider" => "anthropic",
        "model" => "claude-sonnet-test",
        "schema_version" => ExecutionBrief.schema_version(),
        "fallback_chain" => ["anthropic", "openai", "openrouter", "ollama"],
        "occupation" => "healthcare",
        "domain_pack" => "healthcare",
        "interview_answers" => %{
          "who_uses_it" => "Front desk and clinic admins",
          "data_involved" => "Patient names and insurance notes",
          "first_release" => "Intake, review, export",
          "constraints" => "Approval before deploy"
        }
      },
      stringify_keys(overrides)
    )
  end

  def execution_brief_fixture(opts \\ []) do
    payload = provider_brief_payload(Keyword.get(opts, :payload, %{}))
    metadata = compiler_metadata(Keyword.get(opts, :compiler, %{}))

    {:ok, brief} = ExecutionBrief.from_provider_response(payload, metadata)
    brief
  end

  def sample_intent_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "occupation" => "healthcare",
        "agent" => "claude",
        "project_name" => "Clinic Intake",
        "idea" =>
          "Build a patient intake workflow for a small clinic with staff review and exports.",
        "interview_answers" => %{
          "who_uses_it" => "Front desk staff and clinic admins",
          "data_involved" => "Patient names, insurance notes, scheduling details",
          "first_release" => "Intake form, review queue, export",
          "constraints" => "Local-first deploy, approval before production"
        }
      },
      stringify_keys(overrides)
    )
  end

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end
end
