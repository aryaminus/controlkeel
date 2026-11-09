defmodule ControlKeel.Governance.WorkspaceAgentTest do
  use ControlKeel.DataCase

  alias ControlKeel.Governance.WorkspaceAgent
  alias ControlKeel.Mission

  describe "register/1" do
    test "creates a specialized agent" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Agent",
          slug: "agent-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active",
          org_id: ControlKeel.AccountsFixtures.org_fixture().id
        })

      assert {:ok, agent} =
               WorkspaceAgent.register(%{
                 workspace_id: workspace.id,
                 name: "Helper Bot",
                 role: "specialized",
                 agent_type: "claude-code"
               })

      assert agent.role == "specialized"
      assert agent.status == "active"
      assert String.starts_with?(agent.external_id, "agent_")
    end

    test "creates a primary agent" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Primary",
          slug: "primary-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active",
          org_id: ControlKeel.AccountsFixtures.org_fixture().id
        })

      assert {:ok, agent} =
               WorkspaceAgent.register(%{
                 workspace_id: workspace.id,
                 name: "Super Agent",
                 role: "primary",
                 agent_type: "claude-code"
               })

      assert agent.role == "primary"
    end

    test "allows multiple specialized agents per workspace" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Multi",
          slug: "multi-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active",
          org_id: ControlKeel.AccountsFixtures.org_fixture().id
        })

      assert {:ok, _a} =
               WorkspaceAgent.register(%{
                 workspace_id: workspace.id,
                 name: "Spec A",
                 role: "specialized",
                 agent_type: "claude-code"
               })

      assert {:ok, _b} =
               WorkspaceAgent.register(%{
                 workspace_id: workspace.id,
                 name: "Spec B",
                 role: "specialized",
                 agent_type: "cursor"
               })
    end

    test "rejects second primary for same workspace" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Dup",
          slug: "dup-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active",
          org_id: ControlKeel.AccountsFixtures.org_fixture().id
        })

      {:ok, _first} =
        WorkspaceAgent.register(%{
          workspace_id: workspace.id,
          name: "First",
          role: "primary",
          agent_type: "claude-code"
        })

      assert {:error, :primary_exists} =
               WorkspaceAgent.register(%{
                 workspace_id: workspace.id,
                 name: "Second",
                 role: "primary",
                 agent_type: "cursor"
               })
    end
  end

  describe "health/1" do
    test "returns health summary for an agent" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Health",
          slug: "health-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active",
          org_id: ControlKeel.AccountsFixtures.org_fixture().id
        })

      {:ok, agent} =
        WorkspaceAgent.register(%{
          workspace_id: workspace.id,
          name: "Healthy Agent",
          role: "specialized",
          agent_type: "claude-code",
          budget_cents: 10_000
        })

      health = WorkspaceAgent.health(agent.id)
      assert health.health_status == "idle"
      assert health.budget_utilization_percent == 0.0
    end
  end

  describe "retire/1" do
    test "retires a specialized agent" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Retire",
          slug: "retire-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active",
          org_id: ControlKeel.AccountsFixtures.org_fixture().id
        })

      {:ok, agent} =
        WorkspaceAgent.register(%{
          workspace_id: workspace.id,
          name: "Old Agent",
          role: "specialized",
          agent_type: "claude-code"
        })

      assert {:ok, retired} = WorkspaceAgent.retire(agent.id)
      assert retired.status == "retired"
    end

    test "refuses to retire primary agent" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "NoRetire",
          slug: "noretire-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active",
          org_id: ControlKeel.AccountsFixtures.org_fixture().id
        })

      {:ok, agent} =
        WorkspaceAgent.register(%{
          workspace_id: workspace.id,
          name: "Primary Agent",
          role: "primary",
          agent_type: "claude-code"
        })

      assert {:error, :cannot_retire_primary} = WorkspaceAgent.retire(agent.id)
    end
  end
end
