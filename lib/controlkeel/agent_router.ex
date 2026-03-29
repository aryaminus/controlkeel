defmodule ControlKeel.AgentRouter do
  @moduledoc """
  Layer 3: Agent Router.

  Selects the best agent for a task based on task type, security tier,
  budget remaining, and domain. Returns a recommendation with rationale.

  Supported agents (67 total across 9 categories):

  Local IDEs:          claude-code, cursor, windsurf, kiro, augment, amp
  Local CLIs:          aider, opencode, codex-cli, antigravity, continue, ollama
  Cloud platforms:     bolt, replit, lovable, v0, factory, devin, ai-studio, codex, gemini-cli, generic-cli
  Review / spec:       coderabbit, copilot, qodo, specpilot, chatprd, specced
  LLM providers:       openai, anthropic, gemini, deepseek, mistral, openrouter, glm, kimi, qwen,
                       bedrock, vertex-ai, azure-openai, groq, together, cohere, huggingface, replicate
  Frameworks:          crewai, langchain, deepagents, nemo-guardrails,
                       langgraph, autogen, semantic-kernel, dspy, haystack, dify, flowise, n8n, prefect, mastra
  Managed platforms:   bedrock-agents, azure-ai-agent, vertex-ai-agent
  Workflow automation: zapier, make
  Observability / ops: agentops, vellum, promptflow
  """

  alias ControlKeel.PolicyTraining

  # ── Capability key reference ─────────────────────────────────────────────────
  # :repo_edit         — can read/write repository files
  # :file_write        — general file write
  # :bash              — can execute shell commands
  # :mcp               — supports Model Context Protocol
  # :git               — native git operations
  # :ui_prototype      — UI/component prototyping
  # :full_stack_scaffold — full-stack project scaffolding
  # :deploy            — deployment / infra management
  # :code_review       — code quality and security review
  # :pr_review         — pull request review and comment
  # :test_gen          — automated test generation
  # :spec_gen          — spec / PRD generation
  # :multi_agent       — orchestrates sub-agents
  # :llm_provider      — raw LLM API (not a full coding agent)
  # :rag               — retrieval-augmented generation / vector search
  # :workflow          — workflow automation / trigger-based integration
  # :observability     — agent monitoring, tracing, session replay
  # :prompt_management — prompt versioning, evaluation, deployment ops
  # :skills            — supports AgentSkills discovery and activation via ck_skill_list/ck_skill_load

  @agents %{
    # ── Category A: Local IDEs ───────────────────────────────────────────────
    "claude-code" => %{
      name: "Claude Code",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :git],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.72,
      local: true
    },
    "cursor" => %{
      name: "Cursor",
      capabilities: [:repo_edit, :file_write, :bash, :mcp],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.65,
      local: true
    },
    "windsurf" => %{
      name: "Windsurf",
      capabilities: [:repo_edit, :file_write, :bash, :mcp],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.63,
      local: true
    },
    "kiro" => %{
      name: "Kiro (Amazon)",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.60,
      local: true
    },
    "augment" => %{
      name: "Augment Code",
      capabilities: [:repo_edit, :file_write, :mcp],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.58,
      local: true
    },
    "amp" => %{
      name: "Amp (Sourcegraph)",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :git, :skills],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.60,
      local: true
    },
    # ── Category B: Local CLIs ───────────────────────────────────────────────
    "aider" => %{
      name: "Aider",
      capabilities: [:repo_edit, :file_write, :git, :bash],
      cost_tier: :free,
      security_tier: :critical,
      swe_bench_score: 0.56,
      local: true
    },
    "opencode" => %{
      name: "OpenCode",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :free,
      security_tier: :critical,
      swe_bench_score: 0.52,
      local: true
    },
    "codex-cli" => %{
      name: "Codex CLI",
      capabilities: [:repo_edit, :file_write, :bash],
      cost_tier: :low,
      security_tier: :high,
      swe_bench_score: 0.64,
      local: true
    },
    "antigravity" => %{
      name: "Antigravity",
      capabilities: [:repo_edit, :file_write, :bash],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.44,
      local: true
    },
    "continue" => %{
      name: "Continue",
      capabilities: [:repo_edit, :file_write, :mcp],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.50,
      local: true
    },
    "ollama" => %{
      name: "Ollama (local)",
      capabilities: [:repo_edit, :file_write],
      cost_tier: :free,
      security_tier: :critical,
      swe_bench_score: 0.45,
      local: true
    },
    # ── Category C: Cloud Platforms & Scaffolders ────────────────────────────
    # gemini-cli calls Google's remote API by default, so local: false
    "gemini-cli" => %{
      name: "Gemini CLI",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.57,
      local: false
    },
    "bolt" => %{
      name: "Bolt",
      capabilities: [:ui_prototype, :full_stack_scaffold],
      cost_tier: :low,
      security_tier: :low,
      swe_bench_score: 0.40,
      local: false
    },
    "replit" => %{
      name: "Replit",
      capabilities: [:ui_prototype, :full_stack_scaffold, :deploy],
      cost_tier: :low,
      security_tier: :low,
      swe_bench_score: 0.38,
      local: false
    },
    "lovable" => %{
      name: "Lovable",
      capabilities: [:ui_prototype, :full_stack_scaffold],
      cost_tier: :low,
      security_tier: :low,
      swe_bench_score: 0.41,
      local: false
    },
    "v0" => %{
      name: "v0 (Vercel)",
      capabilities: [:ui_prototype],
      cost_tier: :low,
      security_tier: :low,
      swe_bench_score: 0.36,
      local: false
    },
    "factory" => %{
      name: "Factory",
      capabilities: [:repo_edit, :full_stack_scaffold, :deploy],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.54,
      local: false
    },
    "devin" => %{
      name: "Devin (Cognition)",
      capabilities: [:repo_edit, :file_write, :bash, :deploy],
      cost_tier: :high,
      security_tier: :medium,
      swe_bench_score: 0.51,
      local: false
    },
    "ai-studio" => %{
      name: "Google AI Studio",
      capabilities: [:ui_prototype, :full_stack_scaffold],
      cost_tier: :low,
      security_tier: :low,
      swe_bench_score: 0.40,
      local: false
    },
    "codex" => %{
      name: "OpenAI Codex",
      capabilities: [:repo_edit, :file_write, :bash],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.68,
      local: false
    },
    "generic-cli" => %{
      name: "Generic CLI",
      capabilities: [:repo_edit, :file_write, :bash],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.50,
      local: false
    },
    # ── Category D: Code Review & Spec Tools ─────────────────────────────────
    "coderabbit" => %{
      name: "CodeRabbit",
      capabilities: [:code_review, :pr_review],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.72,
      local: false
    },
    "copilot" => %{
      name: "GitHub Copilot",
      capabilities: [:repo_edit, :code_review, :pr_review],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.64,
      local: false
    },
    "qodo" => %{
      name: "Qodo",
      capabilities: [:code_review, :test_gen],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.66,
      local: false
    },
    "specpilot" => %{
      name: "SpecPilot",
      capabilities: [:spec_gen, :code_review],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.55,
      local: false
    },
    "chatprd" => %{
      name: "ChatPRD",
      capabilities: [:spec_gen],
      cost_tier: :low,
      security_tier: :low,
      swe_bench_score: 0.50,
      local: false
    },
    "specced" => %{
      name: "Specced",
      capabilities: [:spec_gen],
      cost_tier: :low,
      security_tier: :low,
      swe_bench_score: 0.48,
      local: false
    },
    # ── Category E: LLM Providers ────────────────────────────────────────────
    "openai" => %{
      name: "OpenAI",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.70,
      local: false
    },
    "anthropic" => %{
      name: "Anthropic",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.74,
      local: false
    },
    "gemini" => %{
      name: "Google Gemini",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.65,
      local: false
    },
    "deepseek" => %{
      name: "DeepSeek",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.62,
      local: false
    },
    "mistral" => %{
      name: "Mistral AI",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.58,
      local: false
    },
    "openrouter" => %{
      name: "OpenRouter",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.60,
      local: false
    },
    "glm" => %{
      name: "Zhipu GLM",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.52,
      local: false
    },
    "kimi" => %{
      name: "Kimi (Moonshot)",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.55,
      local: false
    },
    "qwen" => %{
      name: "Qwen (Alibaba)",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.58,
      local: false
    },
    # Cloud managed LLM services with enterprise IAM auth
    "bedrock" => %{
      name: "AWS Bedrock",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.70,
      local: false
    },
    "vertex-ai" => %{
      name: "Google Vertex AI",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.68,
      local: false
    },
    "azure-openai" => %{
      name: "Azure OpenAI",
      capabilities: [:llm_provider, :repo_edit],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.71,
      local: false
    },
    # Fast / cheap inference APIs
    "groq" => %{
      name: "Groq Cloud",
      capabilities: [:llm_provider],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.64,
      local: false
    },
    "together" => %{
      name: "Together AI",
      capabilities: [:llm_provider],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.63,
      local: false
    },
    "cohere" => %{
      name: "Cohere",
      capabilities: [:llm_provider, :rag],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.60,
      local: false
    },
    "huggingface" => %{
      name: "Hugging Face Inference",
      capabilities: [:llm_provider],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.58,
      local: false
    },
    "replicate" => %{
      name: "Replicate",
      capabilities: [:llm_provider],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.58,
      local: false
    },
    # ── Category F: Orchestration Frameworks ─────────────────────────────────
    "crewai" => %{
      name: "CrewAI",
      capabilities: [:multi_agent, :repo_edit],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.48,
      local: true
    },
    "langchain" => %{
      name: "LangChain",
      capabilities: [:multi_agent, :llm_provider],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.46,
      local: true
    },
    "deepagents" => %{
      name: "DeepAgents",
      capabilities: [:multi_agent, :repo_edit],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.44,
      local: true
    },
    "nemo-guardrails" => %{
      name: "NeMo Guardrails",
      capabilities: [:multi_agent, :llm_provider],
      cost_tier: :free,
      security_tier: :critical,
      swe_bench_score: 0.42,
      local: true
    },
    # Extended open-source frameworks
    "langgraph" => %{
      name: "LangGraph",
      capabilities: [:multi_agent, :repo_edit],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.54,
      local: true
    },
    "autogen" => %{
      name: "Microsoft AutoGen",
      capabilities: [:multi_agent, :llm_provider],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.52,
      local: true
    },
    "semantic-kernel" => %{
      name: "Semantic Kernel",
      capabilities: [:multi_agent, :llm_provider, :mcp],
      cost_tier: :free,
      security_tier: :high,
      swe_bench_score: 0.56,
      local: true
    },
    "dspy" => %{
      name: "DSPy",
      capabilities: [:llm_provider],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.50,
      local: true
    },
    "haystack" => %{
      name: "Haystack (deepset)",
      capabilities: [:multi_agent, :rag],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.52,
      local: true
    },
    "dify" => %{
      name: "Dify",
      capabilities: [:multi_agent, :rag, :repo_edit],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.54,
      local: true
    },
    "flowise" => %{
      name: "Flowise",
      capabilities: [:multi_agent, :repo_edit],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.48,
      local: true
    },
    "n8n" => %{
      name: "n8n",
      capabilities: [:workflow, :multi_agent],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.46,
      local: true
    },
    "prefect" => %{
      name: "Prefect",
      capabilities: [:workflow],
      cost_tier: :free,
      security_tier: :high,
      swe_bench_score: 0.44,
      local: true
    },
    "mastra" => %{
      name: "Mastra",
      capabilities: [:multi_agent, :repo_edit],
      cost_tier: :free,
      security_tier: :medium,
      swe_bench_score: 0.52,
      local: true
    },
    # ── Category G: Managed Agent Platforms ──────────────────────────────────
    # Cloud-hosted agent services with IAM / enterprise auth and native MCP
    "bedrock-agents" => %{
      name: "AWS Bedrock Agents",
      capabilities: [:multi_agent, :deploy, :rag, :mcp],
      cost_tier: :high,
      security_tier: :high,
      swe_bench_score: 0.68,
      local: false
    },
    "azure-ai-agent" => %{
      name: "Azure AI Agent Service",
      capabilities: [:multi_agent, :deploy, :mcp],
      cost_tier: :high,
      security_tier: :high,
      swe_bench_score: 0.70,
      local: false
    },
    "vertex-ai-agent" => %{
      name: "Vertex AI Agent Builder",
      capabilities: [:multi_agent, :deploy, :rag, :mcp],
      cost_tier: :high,
      security_tier: :high,
      swe_bench_score: 0.66,
      local: false
    },
    # ── Category H: Workflow Automation ──────────────────────────────────────
    # Cloud SaaS connectors — low security tier, cloud-only
    "zapier" => %{
      name: "Zapier",
      capabilities: [:workflow],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.32,
      local: false
    },
    "make" => %{
      name: "Make (Integromat)",
      capabilities: [:workflow],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.30,
      local: false
    },
    # ── Category I: Observability & Prompt Ops ────────────────────────────────
    "agentops" => %{
      name: "AgentOps",
      capabilities: [:observability],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.25,
      local: false
    },
    "vellum" => %{
      name: "Vellum",
      capabilities: [:prompt_management],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.48,
      local: false
    },
    "promptflow" => %{
      name: "Azure Prompt Flow",
      capabilities: [:prompt_management, :multi_agent],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.52,
      local: false
    }
  }

  @doc """
  Route a task to the best agent.

  Returns `{:ok, %{agent: agent_id, rationale: [string], warnings: [string]}}`.

  Options:
  - `:risk_tier` — "low", "medium", "high", "critical". Default: "medium"
  - `:task_type` — hint for the router (`:ui`, `:backend`, `:refactor`, `:test`, `:deploy`, `:review`, `:spec`)
  - `:budget_remaining_cents` — remaining session budget; routes away from expensive agents if low
  - `:allowed_agents` — list of agent ids to restrict routing to
  """
  def route(task_title, opts \\ []) do
    risk_tier = Keyword.get(opts, :risk_tier, "medium")
    task_type = Keyword.get(opts, :task_type) || infer_task_type(task_title)
    budget_remaining = Keyword.get(opts, :budget_remaining_cents)
    allowed = Keyword.get(opts, :allowed_agents, Map.keys(@agents))
    domain_pack = Keyword.get(opts, :domain_pack, "software")

    candidates =
      @agents
      |> Enum.filter(fn {id, _} -> id in allowed end)
      |> Enum.filter(fn {_, agent} -> security_ok?(agent, risk_tier) end)
      |> Enum.filter(fn {_, agent} -> capability_match?(agent, task_type) end)
      |> Enum.filter(fn {_, agent} -> budget_ok?(agent, budget_remaining) end)

    case candidates do
      [] ->
        {:error, :no_suitable_agent,
         "No agent satisfies the security tier (#{risk_tier}) and task type (#{task_type}) constraints. Consider using ollama or aider for high-sensitivity tasks."}

      ranked ->
        scored = rank_candidates(ranked, task_type, risk_tier, budget_remaining, domain_pack)
        [best | rest] = scored
        {best_id, best_agent} = {best.id, best.agent}
        rationale = build_rationale(best_id, best_agent, task_type, risk_tier)
        warnings = build_warnings(best_agent, risk_tier, budget_remaining)

        :telemetry.execute(
          [:controlkeel, :agent_router, :policy_used],
          %{count: 1, score: best.score},
          %{
            agent_id: best_id,
            policy_source: best.policy_source,
            artifact_version: best.artifact_version
          }
        )

        {:ok,
         %{
           agent: best_id,
           agent_name: best_agent.name,
           task_type: task_type,
           rationale: rationale,
           warnings: warnings,
           alternatives: alternative_summary(rest),
           policy_source: best.policy_source,
           artifact_version: best.artifact_version
         }}
    end
  end

  @doc "List all supported agents with their capabilities."
  def list_agents, do: @agents

  @doc "Get a specific agent's profile."
  def get_agent(id), do: Map.get(@agents, id)

  # ── Internals ────────────────────────────────────────────────────────────────

  defp infer_task_type(title) do
    t = String.downcase(title)

    cond do
      Regex.match?(
        ~r/\b(ui|interface|component|page|form|modal|layout|design|frontend|react|vue|svelte)\b/,
        t
      ) ->
        :ui

      Regex.match?(~r/\b(deploy|release|publish|docker|kubernetes|k8s|ci|cd|pipeline|infra)\b/, t) ->
        :deploy

      Regex.match?(~r/\b(test|spec\s+coverage|coverage|assertion|rspec|pytest|jest|vitest)\b/, t) ->
        :test

      Regex.match?(~r/\b(refactor|rename|extract|cleanup|dead.?code|lint|format|migrate)\b/, t) ->
        :refactor

      Regex.match?(~r/\b(review|pull.?request|code.?review|audit.?report)\b/, t) ->
        :review

      Regex.match?(~r/\b(prd|requirement|design.?doc|rfc|proposal)\b/, t) ->
        :spec

      Regex.match?(
        ~r/\b(workflow|automate|automation|trigger|zap|integration|connector|webhook|n8n|zapier|make\.com)\b/,
        t
      ) ->
        :workflow

      Regex.match?(
        ~r/\b(skill|skills|activate.?skill|load.?skill|agentskill|skill.?load|skill.?list)\b/,
        t
      ) ->
        :skill

      Regex.match?(
        ~r/\b(api|endpoint|route|controller|handler|middleware|auth|database|migration|schema)\b/,
        t
      ) ->
        :backend

      true ->
        :backend
    end
  end

  defp security_ok?(%{security_tier: :critical}, _risk), do: true

  defp security_ok?(%{security_tier: :high}, risk) when risk in ["low", "medium", "high"],
    do: true

  defp security_ok?(%{security_tier: :medium}, risk) when risk in ["low", "medium"], do: true
  defp security_ok?(%{security_tier: :low}, "low"), do: true
  defp security_ok?(_, _), do: false

  defp capability_match?(%{capabilities: caps}, :ui),
    do: :ui_prototype in caps or :full_stack_scaffold in caps or :repo_edit in caps

  defp capability_match?(%{capabilities: caps}, :deploy), do: :deploy in caps or :bash in caps

  defp capability_match?(%{capabilities: caps}, :review),
    do: :code_review in caps or :pr_review in caps or :repo_edit in caps

  defp capability_match?(%{capabilities: caps}, :spec),
    do: :spec_gen in caps or :llm_provider in caps or :repo_edit in caps

  defp capability_match?(%{capabilities: caps}, :workflow),
    do: :workflow in caps or :multi_agent in caps or :bash in caps

  # Any MCP-capable agent can discover and activate AgentSkills via ck_skill_list/ck_skill_load
  defp capability_match?(%{capabilities: caps}, :skill),
    do: :mcp in caps or :repo_edit in caps

  defp capability_match?(_, _), do: true

  defp budget_ok?(_, nil), do: true
  defp budget_ok?(%{cost_tier: :free}, _), do: true
  defp budget_ok?(%{cost_tier: :low}, remaining) when remaining > 50, do: true
  defp budget_ok?(%{cost_tier: :medium}, remaining) when remaining > 200, do: true
  defp budget_ok?(%{cost_tier: :high}, remaining) when remaining > 1000, do: true
  defp budget_ok?(_, _), do: false

  defp rank_candidates(candidates, task_type, risk_tier, budget_remaining, domain_pack) do
    active_artifact = PolicyTraining.active_artifact("router")
    budget_tier = budget_tier(budget_remaining)

    Enum.map(candidates, fn {id, agent} ->
      learned_score =
        case active_artifact do
          %{artifact: _artifact} = artifact ->
            PolicyTraining.score_router_candidate(artifact, id, agent, %{
              "task_type" => task_type,
              "risk_tier" => risk_tier,
              "domain_pack" => domain_pack,
              "budget_tier" => budget_tier
            })

          _ ->
            {:error, :no_active_artifact}
        end

      case learned_score do
        {:ok, learned} ->
          %{
            id: id,
            agent: agent,
            score: learned.score,
            policy_source: learned.policy_source,
            artifact_version: learned.artifact_version
          }

        {:error, _reason} ->
          %{
            id: id,
            agent: agent,
            score: score(agent, task_type, risk_tier),
            policy_source: "heuristic",
            artifact_version: nil
          }
      end
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp score(
         %{swe_bench_score: swe, security_tier: sec, local: local} = agent,
         task_type,
         risk_tier
       ) do
    security_bonus =
      case {sec, risk_tier} do
        {:critical, _} -> 0.3
        {:high, "high"} -> 0.2
        {:high, "critical"} -> 0.1
        _ -> 0.0
      end

    local_bonus = if local, do: 0.1, else: 0.0

    task_bonus =
      case task_type do
        :ui ->
          if :ui_prototype in agent.capabilities, do: 0.2, else: 0.0

        :review ->
          if :code_review in agent.capabilities or :pr_review in agent.capabilities,
            do: 0.2,
            else: 0.0

        :spec ->
          if :spec_gen in agent.capabilities, do: 0.2, else: 0.0

        :workflow ->
          if :workflow in agent.capabilities, do: 0.2, else: 0.0

        :skill ->
          if :mcp in agent.capabilities, do: 0.25, else: 0.0

        _ ->
          0.0
      end

    swe + security_bonus + local_bonus + task_bonus
  end

  defp build_rationale(_agent_id, agent, task_type, risk_tier) do
    [
      "Selected #{agent.name} for task type: #{task_type}",
      "SWE-bench score: #{trunc(agent.swe_bench_score * 100)}%",
      "Security tier: #{agent.security_tier} (required: #{risk_tier})",
      if(agent.local, do: "Runs locally — no data sent to external servers", else: nil)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp build_warnings(agent, risk_tier, budget_remaining) do
    [
      if(!agent.local and risk_tier in ["high", "critical"],
        do:
          "#{agent.name} sends data to external servers. Verify data classification before proceeding.",
        else: nil
      ),
      if(budget_remaining && budget_remaining < 100,
        do:
          "Budget is low ($#{Float.round(budget_remaining / 100, 2)} remaining). Consider switching to Ollama or Aider (free).",
        else: nil
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp alternative_summary(candidates) do
    candidates
    |> Enum.take(2)
    |> Enum.map(fn candidate ->
      %{
        agent: candidate.id,
        name: candidate.agent.name,
        policy_source: candidate.policy_source,
        artifact_version: candidate.artifact_version
      }
    end)
  end

  defp budget_tier(nil), do: "medium"
  defp budget_tier(remaining) when remaining <= 50, do: "free"
  defp budget_tier(remaining) when remaining <= 200, do: "low"
  defp budget_tier(remaining) when remaining <= 1_000, do: "medium"
  defp budget_tier(_remaining), do: "high"
end
