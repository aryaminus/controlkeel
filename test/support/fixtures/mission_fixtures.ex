defmodule ControlKeel.MissionFixtures do
  @moduledoc false

  alias ControlKeel.Mission

  def workspace_fixture(attrs \\ %{}) do
    {:ok, workspace} =
      attrs
      |> Enum.into(%{
        agent: "claude",
        budget_cents: 5_000,
        compliance_profile: "OWASP Top 10, GDPR",
        industry: "web",
        name: "ControlKeel Workspace",
        slug: unique_slug(),
        status: "active"
      })
      |> Mission.create_workspace()

    workspace
  end

  def session_fixture(attrs \\ %{}) do
    workspace = Map.get_lazy(attrs, :workspace, fn -> workspace_fixture() end)

    {:ok, session} =
      attrs
      |> Enum.into(%{
        budget_cents: 5_000,
        daily_budget_cents: 5_000,
        execution_brief: %{"recommended_stack" => "Phoenix"},
        objective: "Build the first governed workflow",
        risk_tier: "high",
        spent_cents: 600,
        status: "in_progress",
        title: "ControlKeel Session",
        workspace_id: workspace.id
      })
      |> Map.delete(:workspace)
      |> Mission.create_session()

    session
  end

  def task_fixture(attrs \\ %{}) do
    session = Map.get_lazy(attrs, :session, fn -> session_fixture() end)

    {:ok, task} =
      attrs
      |> Enum.into(%{
        estimated_cost_cents: 40,
        metadata: %{},
        position: 1,
        status: "queued",
        title: "Lock architecture",
        validation_gate: "Brief approved",
        session_id: session.id
      })
      |> Map.delete(:session)
      |> Mission.create_task()

    task
  end

  def finding_fixture(attrs \\ %{}) do
    session = Map.get_lazy(attrs, :session, fn -> session_fixture() end)

    {:ok, finding} =
      attrs
      |> Enum.into(%{
        auto_resolved: false,
        category: "security",
        metadata: %{},
        plain_message: "Budget and secret handling need a review.",
        rule_id: "security.sample",
        severity: "high",
        status: "open",
        title: "Sample finding",
        session_id: session.id
      })
      |> Map.delete(:session)
      |> Mission.create_finding()

    finding
  end

  defp unique_slug do
    "workspace-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
