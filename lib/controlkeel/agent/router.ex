defmodule ControlKeel.Agent.Router do
  @moduledoc """
  Layer 3: Agent Router.

  Selects the best agent for a task based on task type, security tier,
  budget remaining, and domain. Returns a recommendation with rationale.

  Product routing is intentionally bounded to coding/review/runtime agents. Raw
  LLM providers, generic frameworks, workflow tools, and observability products
  are configured through provider/runtime integrations instead of being ranked as
  first-class agents.
  """

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

  # Routing only names agents ControlKeel integrates with (see
  # `Agent.Integration.catalog/0`), so a recommendation is always attachable.
  @agents %{
    "claude-code" => %{
      name: "Claude Code",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :git],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.72,
      context_window_k: 200,
      local: true
    },
    "codex-cli" => %{
      name: "Codex CLI",
      capabilities: [:repo_edit, :file_write, :bash],
      cost_tier: :low,
      security_tier: :high,
      swe_bench_score: 0.64,
      context_window_k: 128,
      local: true
    },
    "cursor" => %{
      name: "Cursor",
      capabilities: [:repo_edit, :file_write, :bash, :mcp],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.65,
      context_window_k: 200,
      local: true
    },
    "copilot" => %{
      name: "GitHub Copilot",
      capabilities: [:repo_edit, :code_review, :pr_review],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.64,
      local: false
    },
    "antigravity" => %{
      name: "Antigravity",
      capabilities: [:repo_edit, :file_write, :bash],
      cost_tier: :low,
      security_tier: :medium,
      swe_bench_score: 0.44,
      local: true
    },
    "opencode" => %{
      name: "OpenCode",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :free,
      security_tier: :critical,
      swe_bench_score: 0.52,
      context_window_k: 200,
      local: true
    },
    "windsurf" => %{
      name: "Windsurf",
      capabilities: [:repo_edit, :file_write, :bash, :mcp],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.63,
      context_window_k: 128,
      local: true
    },
    "kiro" => %{
      name: "Kiro (Amazon)",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.60,
      context_window_k: 128,
      local: true
    },
    "amp" => %{
      name: "Amp (Sourcegraph)",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :git, :skills],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.60,
      context_window_k: 200,
      local: true
    },
    "augment" => %{
      name: "Augment Code",
      capabilities: [:repo_edit, :file_write, :mcp],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.58,
      context_window_k: 200,
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
    "devin" => %{
      name: "Devin (Cognition)",
      capabilities: [:repo_edit, :file_write, :bash, :deploy],
      cost_tier: :high,
      security_tier: :medium,
      swe_bench_score: 0.51,
      local: false
    },
    "droid" => %{
      name: "Factory Droid",
      capabilities: [:repo_edit, :full_stack_scaffold, :deploy],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.54,
      local: false
    },
    "cline" => %{
      name: "Cline",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.55,
      local: true
    },
    "kilo" => %{
      name: "Kilo Code",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.55,
      local: true
    },
    "roo-code" => %{
      name: "Roo Code",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :medium,
      security_tier: :high,
      swe_bench_score: 0.55,
      local: true
    },
    "goose" => %{
      name: "Goose",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :low,
      security_tier: :high,
      swe_bench_score: 0.50,
      local: true
    },
    "pi" => %{
      name: "Pi",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :low,
      security_tier: :high,
      swe_bench_score: 0.50,
      local: true
    },
    "warp" => %{
      name: "Warp",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.55,
      local: false
    },
    "letta-code" => %{
      name: "Letta Code",
      capabilities: [:repo_edit, :file_write, :bash, :mcp, :skills],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.55,
      local: false
    }
  }

  @routable_agent_ids Map.keys(@agents)

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
    agents = routable_agents()
    allowed = Keyword.get(opts, :allowed_agents, Map.keys(agents))
    domain_pack = Keyword.get(opts, :domain_pack, "software")
    token_overhead_k = Keyword.get(opts, :token_overhead_k)

    candidates =
      agents
      |> Enum.filter(fn {id, _} -> id in allowed end)
      |> Enum.filter(fn {_, agent} -> security_ok?(agent, risk_tier) end)
      |> Enum.filter(fn {_, agent} -> capability_match?(agent, task_type) end)
      |> Enum.filter(fn {_, agent} -> budget_ok?(agent, budget_remaining) end)
      |> Enum.filter(fn {_, agent} -> context_window_ok?(agent, token_overhead_k) end)

    case candidates do
      [] ->
        {:error, :no_suitable_agent,
         "No agent satisfies the security tier (#{risk_tier}) and task type (#{task_type}) constraints. Lower the risk tier or allow a critical-tier agent such as OpenCode for high-sensitivity tasks."}

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
  def list_agents, do: routable_agents()

  @doc "Get a specific agent's profile."
  def get_agent(id), do: Map.get(routable_agents(), id)

  # ── Internals ────────────────────────────────────────────────────────────────

  defp routable_agents do
    Map.take(@agents, @routable_agent_ids)
  end

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

  # If no overhead provided, never exclude on context window.
  # If overhead_k is given, require agent context_window_k >= overhead_k.
  # Agents without a context_window_k field assume a 128k window.
  defp context_window_ok?(_agent, nil), do: true

  defp context_window_ok?(agent, overhead_k) do
    Map.get(agent, :context_window_k, 128) >= overhead_k
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

  # Max influence of the learned outcome signal on a candidate's score, and the minimum
  # number of recorded outcomes an agent needs before its learned weight counts. Keeps the
  # static heuristic dominant while letting real outcome history nudge ranking.
  @learning_influence 0.15
  @min_router_outcome_samples 5

  defp rank_candidates(candidates, task_type, risk_tier, budget_remaining, _domain_pack) do
    budget_tier = budget_tier(budget_remaining)
    learned = learned_router_weights()
    learned? = map_size(learned) > 0

    candidates
    |> Enum.map(fn {id, agent} ->
      learned_bias = Map.get(learned, id, 0.0) * @learning_influence

      %{
        id: id,
        agent: agent,
        score: score(agent, task_type, risk_tier) + learned_bias,
        policy_source: if(learned?, do: "heuristic+learned", else: "heuristic"),
        artifact_version: nil,
        budget_tier: budget_tier
      }
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  # Learned routing bias from recorded outcomes (the self-learning loop closing back into
  # routing), gated by a minimum sample size via OutcomeTracker. Resilient by design: any
  # failure or absence of data yields no learned input, so routing degrades to pure
  # heuristic rather than erroring.
  defp learned_router_weights do
    case ControlKeel.Learning.OutcomeTracker.compute_router_weights(
           min_samples: @min_router_outcome_samples
         ) do
      {:ok, weights} when is_map(weights) -> weights
      _ -> %{}
    end
  rescue
    _ -> %{}
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
