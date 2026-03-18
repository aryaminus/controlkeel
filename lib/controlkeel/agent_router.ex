defmodule ControlKeel.AgentRouter do
  @moduledoc """
  Layer 3: Agent Router.

  Selects the best agent for a task based on task type, security tier,
  budget remaining, and domain. Returns a recommendation with rationale.

  Supported agents: claude-code, cursor, codex, bolt, replit, ollama, generic-cli
  """

  @agents %{
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
    "codex" => %{
      name: "OpenAI Codex",
      capabilities: [:repo_edit, :file_write, :bash],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.68,
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
    "ollama" => %{
      name: "Ollama (local)",
      capabilities: [:repo_edit, :file_write],
      cost_tier: :free,
      security_tier: :critical,
      swe_bench_score: 0.45,
      local: true
    },
    "generic-cli" => %{
      name: "Generic CLI",
      capabilities: [:repo_edit, :file_write, :bash],
      cost_tier: :medium,
      security_tier: :medium,
      swe_bench_score: 0.50,
      local: false
    }
  }

  @doc """
  Route a task to the best agent.

  Returns `{:ok, %{agent: agent_id, rationale: [string], warnings: [string]}}`.

  Options:
  - `:risk_tier` — "low", "medium", "high", "critical". Default: "medium"
  - `:task_type` — hint for the router (`:ui`, `:backend`, `:refactor`, `:test`, `:deploy`)
  - `:budget_remaining_cents` — remaining session budget; routes away from expensive agents if low
  - `:allowed_agents` — list of agent ids to restrict routing to
  """
  def route(task_title, opts \\ []) do
    risk_tier = Keyword.get(opts, :risk_tier, "medium")
    task_type = Keyword.get(opts, :task_type) || infer_task_type(task_title)
    budget_remaining = Keyword.get(opts, :budget_remaining_cents)
    allowed = Keyword.get(opts, :allowed_agents, Map.keys(@agents))

    candidates =
      @agents
      |> Enum.filter(fn {id, _} -> id in allowed end)
      |> Enum.filter(fn {_, agent} -> security_ok?(agent, risk_tier) end)
      |> Enum.filter(fn {_, agent} -> capability_match?(agent, task_type) end)
      |> Enum.filter(fn {_, agent} -> budget_ok?(agent, budget_remaining) end)

    case candidates do
      [] ->
        {:error, :no_suitable_agent,
         "No agent satisfies the security tier (#{risk_tier}) and task type (#{task_type}) constraints. Consider using ollama for high-sensitivity tasks."}

      ranked ->
        {best_id, best_agent} = rank(ranked, task_type, risk_tier)
        rationale = build_rationale(best_id, best_agent, task_type, risk_tier)
        warnings = build_warnings(best_agent, risk_tier, budget_remaining)

        {:ok,
         %{
           agent: best_id,
           agent_name: best_agent.name,
           task_type: task_type,
           rationale: rationale,
           warnings: warnings,
           alternatives: alternative_summary(ranked, best_id)
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
      Regex.match?(~r/\b(ui|interface|component|page|form|modal|layout|design|frontend|react|vue|svelte)\b/, t) ->
        :ui

      Regex.match?(~r/\b(deploy|release|publish|docker|kubernetes|k8s|ci|cd|pipeline|infra)\b/, t) ->
        :deploy

      Regex.match?(~r/\b(test|spec|coverage|assertion|rspec|pytest|jest|vitest)\b/, t) ->
        :test

      Regex.match?(~r/\b(refactor|rename|extract|cleanup|dead.?code|lint|format|migrate)\b/, t) ->
        :refactor

      Regex.match?(~r/\b(api|endpoint|route|controller|handler|middleware|auth|database|migration|schema)\b/, t) ->
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
  defp capability_match?(_, _), do: true

  defp budget_ok?(_, nil), do: true
  defp budget_ok?(%{cost_tier: :free}, _), do: true
  defp budget_ok?(%{cost_tier: :low}, remaining) when remaining > 50, do: true
  defp budget_ok?(%{cost_tier: :medium}, remaining) when remaining > 200, do: true
  defp budget_ok?(%{cost_tier: :high}, remaining) when remaining > 1000, do: true
  defp budget_ok?(_, _), do: false

  defp rank(candidates, task_type, risk_tier) do
    Enum.max_by(candidates, fn {_id, agent} ->
      score(agent, task_type, risk_tier)
    end)
  end

  defp score(%{swe_bench_score: swe, security_tier: sec, local: local}, task_type, risk_tier) do
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
        :ui -> if :ui_prototype in Map.get(%{}, :capabilities, []), do: 0.2, else: 0.0
        _ -> 0.0
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
        do: "#{agent.name} sends data to external servers. Verify data classification before proceeding.",
        else: nil
      ),
      if(budget_remaining && budget_remaining < 100,
        do: "Budget is low ($#{Float.round(budget_remaining / 100, 2)} remaining). Consider switching to Ollama (free).",
        else: nil
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp alternative_summary(candidates, chosen_id) do
    candidates
    |> Enum.reject(fn {id, _} -> id == chosen_id end)
    |> Enum.take(2)
    |> Enum.map(fn {id, agent} -> %{agent: id, name: agent.name} end)
  end
end
