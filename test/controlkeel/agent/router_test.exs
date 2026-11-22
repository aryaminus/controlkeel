defmodule ControlKeel.Agent.RouterTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Agent.Router

  # All agents that pass critical security tier (local: true + security_tier :critical or :high)
  @critical_ok [
    "ollama",
    "opencode",
    "claude-code",
    "cursor",
    "windsurf",
    "kiro",
    "augment",
    "amp",
    "codex-cli"
  ]

  describe "route/2 — basic routing" do
    test "returns a recommendation for a backend task" do
      assert {:ok, rec} = Router.route("Build a REST API endpoint")
      assert rec.agent in Map.keys(Router.list_agents())
      assert is_binary(rec.agent_name)
      assert is_list(rec.rationale)
      assert is_list(rec.warnings)
      assert is_list(rec.alternatives)
    end

    test "returns a recommendation for a UI task" do
      assert {:ok, rec} = Router.route("Build a React login form")
      assert rec.task_type == :ui
      assert rec.agent in Map.keys(Router.list_agents())
    end

    test "returns a recommendation for a test task" do
      assert {:ok, rec} = Router.route("Write spec coverage for the auth module")
      assert rec.task_type == :test
    end

    test "returns a recommendation for a refactor task" do
      assert {:ok, rec} = Router.route("Refactor and rename legacy functions")
      assert rec.task_type == :refactor
    end

    test "returns a recommendation for a deploy task" do
      assert {:ok, rec} = Router.route("Deploy to Kubernetes and configure CI pipeline")
      assert rec.task_type == :deploy
    end
  end

  describe "route/2 — new task types :review and :spec" do
    test "infers :review task type" do
      assert {:ok, rec} = Router.route("Review this pull request for security issues")
      assert rec.task_type == :review
    end

    test "infers :spec task type" do
      assert {:ok, rec} = Router.route("Write a prd for the notification system")
      assert rec.task_type == :spec
    end

    test "coderabbit scores highest for :review at low risk (allowed)" do
      assert {:ok, rec} =
               Router.route("Review this PR for security issues",
                 risk_tier: "low",
                 allowed_agents: ["coderabbit", "generic-cli"]
               )

      assert rec.agent == "coderabbit"
    end

    test "specpilot beats generic-cli for :spec task at low risk" do
      assert {:ok, rec} =
               Router.route("Write a prd for the auth module",
                 risk_tier: "low",
                 allowed_agents: ["specpilot", "generic-cli"]
               )

      assert rec.agent == "specpilot"
    end

    test "qodo beats generic-cli for :review task at medium risk" do
      assert {:ok, rec} =
               Router.route("Review the auth module for bugs",
                 risk_tier: "medium",
                 allowed_agents: ["qodo", "generic-cli"]
               )

      assert rec.agent == "qodo"
    end
  end

  describe "route/2 — security tier filtering" do
    test "allows cloud agents for low risk" do
      assert {:ok, rec} = Router.route("Build a marketing page", risk_tier: "low")
      assert is_binary(rec.agent)
    end

    test "prefers local agents for critical risk" do
      assert {:ok, rec} = Router.route("Update patient records", risk_tier: "critical")
      assert rec.agent in @critical_ok
    end

    test "excludes low-security agents for high-risk tasks" do
      assert {:ok, rec} = Router.route("Edit HIPAA-covered data", risk_tier: "high")
      refute rec.agent in ["bolt", "replit", "lovable", "v0", "ai-studio", "chatprd", "specced"]
    end

    test "raw LLM providers are not routable agents" do
      cloud_llm = ["openai", "anthropic", "gemini"]

      assert {:error, :no_suitable_agent, _} =
               Router.route("Implement an API endpoint",
                 risk_tier: "low",
                 allowed_agents: cloud_llm
               )
    end
  end

  describe "route/2 — allowed_agents filtering" do
    test "restricts to allowed agent list" do
      assert {:ok, rec} = Router.route("Build feature", allowed_agents: ["ollama"])
      assert rec.agent == "ollama"
    end

    test "returns error when no allowed agents satisfy constraints" do
      assert {:error, :no_suitable_agent, msg} =
               Router.route("PHI data update",
                 risk_tier: "critical",
                 allowed_agents: ["bolt"]
               )

      assert is_binary(msg)
    end
  end

  describe "route/2 — budget filtering" do
    test "excludes medium-cost agents when budget is very low" do
      assert {:ok, rec} =
               Router.route("Build feature", budget_remaining_cents: 10, risk_tier: "low")

      assert rec.agent in [
               "ollama",
               "opencode",
               "continue"
             ]
    end

    test "allows all agents when budget is sufficient" do
      assert {:ok, rec} = Router.route("Build feature", budget_remaining_cents: 10_000)
      assert is_binary(rec.agent)
    end

    test "excludes devin (high cost tier) when budget < 1000 cents" do
      assert {:error, :no_suitable_agent, _} =
               Router.route("Build feature",
                 budget_remaining_cents: 500,
                 allowed_agents: ["devin"]
               )
    end
  end

  describe "route/2 — UI task scoring" do
    test "bolt receives UI capability bonus for UI tasks over generic-cli" do
      assert {:ok, rec} =
               Router.route("Build a dashboard UI",
                 risk_tier: "low",
                 allowed_agents: ["bolt", "generic-cli"]
               )

      assert rec.agent == "bolt"
    end

    test "lovable beats generic-cli for UI task at low risk" do
      assert {:ok, rec} =
               Router.route("Build a landing page",
                 risk_tier: "low",
                 allowed_agents: ["lovable", "generic-cli"]
               )

      assert rec.agent == "lovable"
    end

    test "replit preferred over codex when budget excludes codex" do
      assert {:ok, rec} =
               Router.route("Build a landing page",
                 risk_tier: "low",
                 allowed_agents: ["replit", "codex"],
                 budget_remaining_cents: 150
               )

      assert rec.agent == "replit"
    end

    test "v0 is a valid UI candidate at low risk" do
      assert {:ok, rec} =
               Router.route("Build a dashboard component",
                 risk_tier: "low",
                 allowed_agents: ["v0"]
               )

      assert rec.agent == "v0"
    end
  end

  describe "route/2 — local CLI category" do
    test "opencode passes critical risk tier" do
      assert {:ok, rec} =
               Router.route("Update PHI data",
                 risk_tier: "critical",
                 allowed_agents: ["opencode"]
               )

      assert rec.agent == "opencode"
    end
  end

  describe "route/2 — cloud scaffolders expanded" do
    test "lovable is included as a UI candidate at low risk" do
      assert {:ok, rec} =
               Router.route("Build a React dashboard",
                 risk_tier: "low",
                 allowed_agents: ["lovable", "v0", "bolt"]
               )

      assert rec.agent in ["lovable", "v0", "bolt"]
    end

    test "v0 excluded for deploy task (only :ui_prototype — no :bash or :deploy capability)" do
      assert {:error, :no_suitable_agent, _} =
               Router.route("Deploy to Kubernetes and configure CI",
                 risk_tier: "low",
                 allowed_agents: ["v0"]
               )
    end
  end

  describe "list_agents/0" do
    test "returns all supported agents" do
      agents = Router.list_agents()
      assert map_size(agents) == 26
    end

    test "contains all expected categories" do
      agents = Router.list_agents()

      # Local IDEs
      assert Map.has_key?(agents, "claude-code")
      assert Map.has_key?(agents, "cursor")
      assert Map.has_key?(agents, "windsurf")
      assert Map.has_key?(agents, "kiro")
      assert Map.has_key?(agents, "augment")
      assert Map.has_key?(agents, "amp")

      # Local CLIs
      assert Map.has_key?(agents, "opencode")
      assert Map.has_key?(agents, "codex-cli")
      assert Map.has_key?(agents, "antigravity")
      assert Map.has_key?(agents, "continue")
      assert Map.has_key?(agents, "ollama")

      # Cloud platforms
      assert Map.has_key?(agents, "bolt")
      assert Map.has_key?(agents, "replit")
      assert Map.has_key?(agents, "lovable")
      assert Map.has_key?(agents, "v0")
      assert Map.has_key?(agents, "factory")
      assert Map.has_key?(agents, "devin")
      assert Map.has_key?(agents, "ai-studio")
      assert Map.has_key?(agents, "codex")
      refute Map.has_key?(agents, "gemini-cli")
      assert Map.has_key?(agents, "generic-cli")

      # Review & spec
      assert Map.has_key?(agents, "coderabbit")
      assert Map.has_key?(agents, "copilot")
      assert Map.has_key?(agents, "qodo")
      assert Map.has_key?(agents, "specpilot")
      assert Map.has_key?(agents, "chatprd")
      assert Map.has_key?(agents, "specced")

      # Non-agent providers/frameworks are intentionally excluded from routing.
      refute Map.has_key?(agents, "openai")
      refute Map.has_key?(agents, "langchain")
      refute Map.has_key?(agents, "n8n")
    end
  end

  describe "get_agent/1" do
    test "returns agent profile" do
      agent = Router.get_agent("claude-code")
      assert agent.name == "Claude Code"
      assert agent.local == true
      assert is_list(agent.capabilities)
    end

    test "returns nil for unknown agent" do
      assert Router.get_agent("unknown-agent") == nil
    end

    test "returns correct profile for kiro" do
      agent = Router.get_agent("kiro")
      assert agent.name == "Kiro (Amazon)"
      assert agent.local == true
      assert :mcp in agent.capabilities
    end

    test "returns correct profile for coderabbit" do
      agent = Router.get_agent("coderabbit")
      assert :code_review in agent.capabilities
      assert :pr_review in agent.capabilities
    end

    test "non-agent provider, framework, workflow, and observability rows are not routable" do
      for id <- ["openai", "anthropic", "dspy", "nemo-guardrails", "zapier", "agentops"] do
        assert Router.get_agent(id) == nil
      end
    end
  end

  describe "route/2 — workflow task type" do
    test "infers :workflow task type" do
      assert {:ok, rec} = Router.route("Set up automation triggers and webhook connectors")
      assert rec.task_type == :workflow
    end

    test "workflow task routes to a real coding/runtime agent, not SaaS automation rows" do
      assert {:ok, rec} =
               Router.route("Set up a webhook automation trigger",
                 risk_tier: "low",
                 allowed_agents: ["generic-cli", "opencode"]
               )

      assert rec.agent in ["generic-cli", "opencode"]
    end
  end
end
