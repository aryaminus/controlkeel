defmodule ControlKeel.AgentRouterTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.AgentRouter
  import ControlKeel.PolicyTrainingFixtures

  # All agents that pass critical security tier (local: true + security_tier :critical or :high)
  @critical_ok [
    "ollama",
    "aider",
    "opencode",
    "nemo-guardrails",
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
      assert {:ok, rec} = AgentRouter.route("Build a REST API endpoint")
      assert rec.agent in Map.keys(AgentRouter.list_agents())
      assert is_binary(rec.agent_name)
      assert is_list(rec.rationale)
      assert is_list(rec.warnings)
      assert is_list(rec.alternatives)
    end

    test "returns a recommendation for a UI task" do
      assert {:ok, rec} = AgentRouter.route("Build a React login form")
      assert rec.task_type == :ui
      assert rec.agent in Map.keys(AgentRouter.list_agents())
    end

    test "returns a recommendation for a test task" do
      assert {:ok, rec} = AgentRouter.route("Write spec coverage for the auth module")
      assert rec.task_type == :test
    end

    test "returns a recommendation for a refactor task" do
      assert {:ok, rec} = AgentRouter.route("Refactor and rename legacy functions")
      assert rec.task_type == :refactor
    end

    test "returns a recommendation for a deploy task" do
      assert {:ok, rec} = AgentRouter.route("Deploy to Kubernetes and configure CI pipeline")
      assert rec.task_type == :deploy
    end
  end

  describe "route/2 — new task types :review and :spec" do
    test "infers :review task type" do
      assert {:ok, rec} = AgentRouter.route("Review this pull request for security issues")
      assert rec.task_type == :review
    end

    test "infers :spec task type" do
      assert {:ok, rec} = AgentRouter.route("Write a prd for the notification system")
      assert rec.task_type == :spec
    end

    test "coderabbit scores highest for :review at low risk (allowed)" do
      assert {:ok, rec} =
               AgentRouter.route("Review this PR for security issues",
                 risk_tier: "low",
                 allowed_agents: ["coderabbit", "generic-cli"]
               )

      assert rec.agent == "coderabbit"
    end

    test "specpilot beats generic-cli for :spec task at low risk" do
      assert {:ok, rec} =
               AgentRouter.route("Write a prd for the auth module",
                 risk_tier: "low",
                 allowed_agents: ["specpilot", "generic-cli"]
               )

      assert rec.agent == "specpilot"
    end

    test "qodo beats generic-cli for :review task at medium risk" do
      assert {:ok, rec} =
               AgentRouter.route("Review the auth module for bugs",
                 risk_tier: "medium",
                 allowed_agents: ["qodo", "generic-cli"]
               )

      assert rec.agent == "qodo"
    end
  end

  describe "route/2 — security tier filtering" do
    test "allows cloud agents for low risk" do
      assert {:ok, rec} = AgentRouter.route("Build a marketing page", risk_tier: "low")
      assert is_binary(rec.agent)
    end

    test "prefers local agents for critical risk" do
      assert {:ok, rec} = AgentRouter.route("Update patient records", risk_tier: "critical")
      assert rec.agent in @critical_ok
    end

    test "excludes low-security agents for high-risk tasks" do
      assert {:ok, rec} = AgentRouter.route("Edit HIPAA-covered data", risk_tier: "high")
      refute rec.agent in ["bolt", "replit", "lovable", "v0", "ai-studio", "chatprd", "specced"]
    end

    test "all cloud LLM providers excluded at critical risk" do
      cloud_llm = [
        "openai",
        "anthropic",
        "gemini",
        "deepseek",
        "mistral",
        "openrouter",
        "glm",
        "kimi",
        "qwen"
      ]

      assert {:error, :no_suitable_agent, _} =
               AgentRouter.route("PHI data update",
                 risk_tier: "critical",
                 allowed_agents: cloud_llm
               )
    end
  end

  describe "route/2 — allowed_agents filtering" do
    test "restricts to allowed agent list" do
      assert {:ok, rec} = AgentRouter.route("Build feature", allowed_agents: ["ollama"])
      assert rec.agent == "ollama"
    end

    test "returns error when no allowed agents satisfy constraints" do
      assert {:error, :no_suitable_agent, msg} =
               AgentRouter.route("PHI data update",
                 risk_tier: "critical",
                 allowed_agents: ["bolt"]
               )

      assert is_binary(msg)
    end
  end

  describe "route/2 — budget filtering" do
    test "excludes medium-cost agents when budget is very low" do
      assert {:ok, rec} =
               AgentRouter.route("Build feature", budget_remaining_cents: 10, risk_tier: "low")

      assert rec.agent in [
               "ollama",
               "aider",
               "opencode",
               "crewai",
               "langchain",
               "deepagents",
               "nemo-guardrails",
               "continue"
             ]
    end

    test "allows all agents when budget is sufficient" do
      assert {:ok, rec} = AgentRouter.route("Build feature", budget_remaining_cents: 10_000)
      assert is_binary(rec.agent)
    end

    test "excludes devin (high cost tier) when budget < 1000 cents" do
      assert {:error, :no_suitable_agent, _} =
               AgentRouter.route("Build feature",
                 budget_remaining_cents: 500,
                 allowed_agents: ["devin"]
               )
    end
  end

  describe "route/2 — UI task scoring" do
    test "bolt receives UI capability bonus for UI tasks over generic-cli" do
      assert {:ok, rec} =
               AgentRouter.route("Build a dashboard UI",
                 risk_tier: "low",
                 allowed_agents: ["bolt", "generic-cli"]
               )

      assert rec.agent == "bolt"
    end

    test "lovable beats generic-cli for UI task at low risk" do
      assert {:ok, rec} =
               AgentRouter.route("Build a landing page",
                 risk_tier: "low",
                 allowed_agents: ["lovable", "generic-cli"]
               )

      assert rec.agent == "lovable"
    end

    test "replit preferred over codex when budget excludes codex" do
      assert {:ok, rec} =
               AgentRouter.route("Build a landing page",
                 risk_tier: "low",
                 allowed_agents: ["replit", "codex"],
                 budget_remaining_cents: 150
               )

      assert rec.agent == "replit"
    end

    test "v0 is a valid UI candidate at low risk" do
      assert {:ok, rec} =
               AgentRouter.route("Build a dashboard component",
                 risk_tier: "low",
                 allowed_agents: ["v0"]
               )

      assert rec.agent == "v0"
    end
  end

  describe "route/2 — LLM providers" do
    test "anthropic routes when allowed and budget sufficient at low risk" do
      assert {:ok, rec} =
               AgentRouter.route("Build a REST endpoint",
                 risk_tier: "low",
                 allowed_agents: ["anthropic"],
                 budget_remaining_cents: 500
               )

      assert rec.agent == "anthropic"
    end

    test "openai routes when allowed at medium risk" do
      assert {:ok, rec} =
               AgentRouter.route("Implement auth middleware",
                 risk_tier: "medium",
                 allowed_agents: ["openai"],
                 budget_remaining_cents: 500
               )

      assert rec.agent == "openai"
    end
  end

  describe "route/2 — local CLI category" do
    test "aider passes critical risk tier" do
      assert {:ok, rec} =
               AgentRouter.route("Update patient records",
                 risk_tier: "critical",
                 allowed_agents: ["aider"]
               )

      assert rec.agent == "aider"
    end

    test "opencode passes critical risk tier" do
      assert {:ok, rec} =
               AgentRouter.route("Update PHI data",
                 risk_tier: "critical",
                 allowed_agents: ["opencode"]
               )

      assert rec.agent == "opencode"
    end
  end

  describe "route/2 — orchestration frameworks" do
    test "nemo-guardrails passes critical risk tier (local + critical security)" do
      assert {:ok, rec} =
               AgentRouter.route("Build governed LLM orchestration layer",
                 risk_tier: "critical",
                 allowed_agents: ["nemo-guardrails"]
               )

      assert rec.agent == "nemo-guardrails"
    end

    test "crewai is excluded at critical risk (medium security tier)" do
      assert {:error, :no_suitable_agent, _} =
               AgentRouter.route("Build multi-agent system",
                 risk_tier: "critical",
                 allowed_agents: ["crewai"]
               )
    end

    test "langchain routes at low risk" do
      assert {:ok, rec} =
               AgentRouter.route("Build LLM orchestration with multiple agents",
                 risk_tier: "low",
                 allowed_agents: ["langchain"]
               )

      assert rec.agent == "langchain"
    end
  end

  describe "route/2 — cloud scaffolders expanded" do
    test "lovable is included as a UI candidate at low risk" do
      assert {:ok, rec} =
               AgentRouter.route("Build a React dashboard",
                 risk_tier: "low",
                 allowed_agents: ["lovable", "v0", "bolt"]
               )

      assert rec.agent in ["lovable", "v0", "bolt"]
    end

    test "v0 excluded for deploy task (only :ui_prototype — no :bash or :deploy capability)" do
      assert {:error, :no_suitable_agent, _} =
               AgentRouter.route("Deploy to Kubernetes and configure CI",
                 risk_tier: "low",
                 allowed_agents: ["v0"]
               )
    end
  end

  describe "list_agents/0" do
    test "returns all supported agents" do
      agents = AgentRouter.list_agents()
      assert map_size(agents) == 67
    end

    test "contains all expected categories" do
      agents = AgentRouter.list_agents()

      # Local IDEs
      assert Map.has_key?(agents, "claude-code")
      assert Map.has_key?(agents, "cursor")
      assert Map.has_key?(agents, "windsurf")
      assert Map.has_key?(agents, "kiro")
      assert Map.has_key?(agents, "augment")
      assert Map.has_key?(agents, "amp")

      # Local CLIs
      assert Map.has_key?(agents, "aider")
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
      assert Map.has_key?(agents, "gemini-cli")
      assert Map.has_key?(agents, "generic-cli")

      # Review & spec
      assert Map.has_key?(agents, "coderabbit")
      assert Map.has_key?(agents, "copilot")
      assert Map.has_key?(agents, "qodo")
      assert Map.has_key?(agents, "specpilot")
      assert Map.has_key?(agents, "chatprd")
      assert Map.has_key?(agents, "specced")

      # LLM providers
      assert Map.has_key?(agents, "openai")
      assert Map.has_key?(agents, "anthropic")
      assert Map.has_key?(agents, "gemini")
      assert Map.has_key?(agents, "deepseek")
      assert Map.has_key?(agents, "mistral")
      assert Map.has_key?(agents, "openrouter")
      assert Map.has_key?(agents, "glm")
      assert Map.has_key?(agents, "kimi")
      assert Map.has_key?(agents, "qwen")

      # Frameworks
      assert Map.has_key?(agents, "crewai")
      assert Map.has_key?(agents, "langchain")
      assert Map.has_key?(agents, "deepagents")
      assert Map.has_key?(agents, "nemo-guardrails")
    end
  end

  describe "get_agent/1" do
    test "returns agent profile" do
      agent = AgentRouter.get_agent("claude-code")
      assert agent.name == "Claude Code"
      assert agent.local == true
      assert is_list(agent.capabilities)
    end

    test "returns nil for unknown agent" do
      assert AgentRouter.get_agent("unknown-agent") == nil
    end

    test "returns correct profile for kiro" do
      agent = AgentRouter.get_agent("kiro")
      assert agent.name == "Kiro (Amazon)"
      assert agent.local == true
      assert :mcp in agent.capabilities
    end

    test "returns correct profile for coderabbit" do
      agent = AgentRouter.get_agent("coderabbit")
      assert :code_review in agent.capabilities
      assert :pr_review in agent.capabilities
    end

    test "returns correct profile for nemo-guardrails" do
      agent = AgentRouter.get_agent("nemo-guardrails")
      assert agent.security_tier == :critical
      assert agent.local == true
      assert :multi_agent in agent.capabilities
    end

    test "anthropic has highest swe_bench_score among original LLM providers" do
      agents = AgentRouter.list_agents()

      llm_providers = [
        "openai",
        "anthropic",
        "gemini",
        "deepseek",
        "mistral",
        "openrouter",
        "glm",
        "kimi",
        "qwen"
      ]

      best =
        llm_providers
        |> Enum.map(&{&1, agents[&1].swe_bench_score})
        |> Enum.max_by(&elem(&1, 1))

      assert elem(best, 0) == "anthropic"
    end

    test "azure-openai has highest swe_bench_score among enterprise cloud LLMs" do
      agents = AgentRouter.list_agents()
      enterprise = ["bedrock", "vertex-ai", "azure-openai"]

      best =
        enterprise
        |> Enum.map(&{&1, agents[&1].swe_bench_score})
        |> Enum.max_by(&elem(&1, 1))

      assert elem(best, 0) == "azure-openai"
    end

    test "enterprise cloud LLMs all have :high security tier" do
      agents = AgentRouter.list_agents()

      for id <- ["bedrock", "vertex-ai", "azure-openai"] do
        assert agents[id].security_tier == :high, "expected #{id} to have :high security tier"
      end
    end

    test "contains all new framework agents" do
      agents = AgentRouter.list_agents()

      for id <- [
            "langgraph",
            "autogen",
            "semantic-kernel",
            "dspy",
            "haystack",
            "dify",
            "flowise",
            "n8n",
            "prefect",
            "mastra"
          ] do
        assert Map.has_key?(agents, id), "missing agent: #{id}"
      end
    end

    test "contains all managed platform agents" do
      agents = AgentRouter.list_agents()

      for id <- ["bedrock-agents", "azure-ai-agent", "vertex-ai-agent"] do
        assert Map.has_key?(agents, id), "missing agent: #{id}"
      end
    end

    test "contains workflow automation and observability agents" do
      agents = AgentRouter.list_agents()

      for id <- ["zapier", "make", "agentops", "vellum", "promptflow"] do
        assert Map.has_key?(agents, id), "missing agent: #{id}"
      end
    end
  end

  describe "route/2 — workflow task type" do
    test "infers :workflow task type" do
      assert {:ok, rec} = AgentRouter.route("Set up automation triggers and webhook connectors")
      assert rec.task_type == :workflow
    end

    test "n8n scores highest for :workflow vs generic-cli at low risk" do
      assert {:ok, rec} =
               AgentRouter.route("Set up a webhook automation trigger",
                 risk_tier: "low",
                 allowed_agents: ["n8n", "generic-cli"]
               )

      assert rec.agent == "n8n"
    end

    test "zapier routes for :workflow task at low risk" do
      assert {:ok, rec} =
               AgentRouter.route("Automate Zapier integrations",
                 risk_tier: "low",
                 allowed_agents: ["zapier"]
               )

      assert rec.agent == "zapier"
    end

    test "make routes for :workflow task at low risk" do
      assert {:ok, rec} =
               AgentRouter.route("Build workflow automation with connectors",
                 risk_tier: "low",
                 allowed_agents: ["make"]
               )

      assert rec.agent == "make"
    end

    test "agentops excluded for :workflow (observability-only, no workflow/multi_agent/bash)" do
      assert {:error, :no_suitable_agent, _} =
               AgentRouter.route("Automate webhook triggers",
                 risk_tier: "low",
                 allowed_agents: ["agentops"]
               )
    end
  end

  describe "route/2 — enterprise cloud LLM providers" do
    test "bedrock routes at high risk (security_tier: :high)" do
      assert {:ok, rec} =
               AgentRouter.route("Build a REST endpoint",
                 risk_tier: "high",
                 allowed_agents: ["bedrock"],
                 budget_remaining_cents: 500
               )

      assert rec.agent == "bedrock"
    end

    test "azure-openai routes at high risk" do
      assert {:ok, rec} =
               AgentRouter.route("Build auth middleware",
                 risk_tier: "high",
                 allowed_agents: ["azure-openai"],
                 budget_remaining_cents: 500
               )

      assert rec.agent == "azure-openai"
    end

    test "bedrock excluded at critical risk (cloud, non-local)" do
      assert {:error, :no_suitable_agent, _} =
               AgentRouter.route("Update PHI data",
                 risk_tier: "critical",
                 allowed_agents: ["bedrock"]
               )
    end

    test "groq routes at low risk (cheap inference)" do
      assert {:ok, rec} =
               AgentRouter.route("Generate code for auth module",
                 risk_tier: "low",
                 allowed_agents: ["groq"],
                 budget_remaining_cents: 100
               )

      assert rec.agent == "groq"
    end

    test "groq excluded at high risk (security_tier: :medium)" do
      assert {:error, :no_suitable_agent, _} =
               AgentRouter.route("Edit HIPAA records",
                 risk_tier: "high",
                 allowed_agents: ["groq"]
               )
    end
  end

  describe "route/2 — managed agent platforms" do
    test "bedrock-agents routes for :deploy task at high risk" do
      assert {:ok, rec} =
               AgentRouter.route("Deploy multi-agent system to production",
                 risk_tier: "high",
                 allowed_agents: ["bedrock-agents"],
                 budget_remaining_cents: 2000
               )

      assert rec.agent == "bedrock-agents"
    end

    test "azure-ai-agent routes for :deploy task at high risk" do
      assert {:ok, rec} =
               AgentRouter.route("Deploy agent pipeline to Kubernetes",
                 risk_tier: "high",
                 allowed_agents: ["azure-ai-agent"],
                 budget_remaining_cents: 2000
               )

      assert rec.agent == "azure-ai-agent"
    end

    test "managed platforms excluded at critical risk (cloud)" do
      for id <- ["bedrock-agents", "azure-ai-agent", "vertex-ai-agent"] do
        assert {:error, :no_suitable_agent, _} =
                 AgentRouter.route("Update PHI data",
                   risk_tier: "critical",
                   allowed_agents: [id]
                 )
      end
    end

    test "managed platforms excluded when budget < 1000 cents" do
      assert {:error, :no_suitable_agent, _} =
               AgentRouter.route("Deploy agent",
                 budget_remaining_cents: 500,
                 allowed_agents: ["azure-ai-agent"]
               )
    end
  end

  describe "route/2 — new frameworks" do
    test "semantic-kernel passes high risk (security_tier: :high, local: true)" do
      assert {:ok, rec} =
               AgentRouter.route("Orchestrate multi-agent system",
                 risk_tier: "high",
                 allowed_agents: ["semantic-kernel"]
               )

      assert rec.agent == "semantic-kernel"
    end

    test "prefect passes high risk (security_tier: :high, local: true)" do
      assert {:ok, rec} =
               AgentRouter.route("Automate data processing with event triggers",
                 risk_tier: "high",
                 allowed_agents: ["prefect"]
               )

      assert rec.agent == "prefect"
    end

    test "langgraph excluded at critical risk (security_tier: :medium)" do
      assert {:error, :no_suitable_agent, _} =
               AgentRouter.route("Build stateful agent",
                 risk_tier: "critical",
                 allowed_agents: ["langgraph"]
               )
    end

    test "n8n beats make for :workflow with free budget (both free-tier, n8n has multi_agent)" do
      assert {:ok, rec} =
               AgentRouter.route("Automate webhook connector flows",
                 risk_tier: "low",
                 allowed_agents: ["n8n", "make"]
               )

      assert rec.agent == "n8n"
    end

    test "vellum excluded for :workflow task (prompt_management only)" do
      assert {:error, :no_suitable_agent, _} =
               AgentRouter.route("Automate webhook triggers",
                 risk_tier: "low",
                 allowed_agents: ["vellum"]
               )
    end
  end

  describe "route/2 — learned policy artifacts" do
    test "uses an active learned router artifact when available" do
      _artifact =
        policy_artifact_fixture(%{
          artifact_type: "router",
          status: "active",
          version: 4,
          artifact:
            default_artifact_payload("router")
            |> Map.put("categorical_vocab", %{
              "task_type" => ["backend", "ui", "__unknown__"],
              "risk_tier" => ["low", "moderate", "high", "critical", "__unknown__"],
              "domain_pack" => ["software", "healthcare", "__unknown__"],
              "budget_tier" => ["free", "low", "medium", "high", "__unknown__"],
              "subject_id" => ["generic-cli", "openai", "__unknown__"],
              "subject_type" => ["agent", "__unknown__"]
            })
            |> Map.put("network", %{
              "layers" => [
                %{
                  "weights" => [
                    List.duplicate(0.0, 19) ++
                      List.duplicate(0.0, 3) ++
                      List.duplicate(0.0, 5) ++
                      List.duplicate(0.0, 3) ++
                      List.duplicate(0.0, 5) ++
                      [4.0, -4.0, 0.0] ++
                      [0.0, 0.0]
                  ],
                  "biases" => [0.0],
                  "activation" => "identity"
                }
              ]
            })
        })

      assert {:ok, rec} =
               AgentRouter.route("Build a REST endpoint",
                 risk_tier: "low",
                 allowed_agents: ["openai", "generic-cli"],
                 budget_remaining_cents: 2_000
               )

      assert rec.agent == "generic-cli"
      assert rec.policy_source == "learned"
      assert rec.artifact_version == 4
    end

    test "falls back to heuristic routing when the active artifact cannot be scored" do
      invalid_artifact =
        policy_artifact_fixture(%{
          artifact_type: "router",
          status: "active",
          version: 5,
          artifact:
            default_artifact_payload("router")
            |> Map.put("network", %{})
        })

      assert {:ok, rec} =
               AgentRouter.route("Build a REST endpoint",
                 risk_tier: "low",
                 allowed_agents: ["openai", "generic-cli"],
                 budget_remaining_cents: 2_000
               )

      assert rec.agent == "openai"
      assert rec.policy_source == "heuristic"
      assert rec.artifact_version == nil
      assert invalid_artifact.id
    end
  end
end
