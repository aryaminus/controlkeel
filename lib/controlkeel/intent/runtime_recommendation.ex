defmodule ControlKeel.Intent.RuntimeRecommendation do
  @moduledoc false

  alias ControlKeel.AgentIntegration
  alias ControlKeel.AgentRuntimes.Registry, as: RuntimeRegistry
  alias ControlKeel.Intent.{ExecutionBrief, ExecutionPosture}
  alias ControlKeel.ProviderBroker

  @approval_keywords ~w(approval approvals review reviewed reviewer human manual signoff)
  @api_runtime_keywords ~w(api apis mcp tool tools integration integrations webhook webhooks oauth queue queues sync async cloudflare worker workers d1 r2 kv edge openapi graphql discovery schema typed typescript javascript executor code-mode codemode search execute single-shot orchestration)
  @virtual_workspace_keywords ~w(virtual workspace filesystem file tree repo search grep find cat bash shell read-only discovery sandbox)

  @undecided %{
    "strategy" => "undecided",
    "recommended_integration" => nil,
    "alternatives" => [],
    "rationale" =>
      "CK needs a populated execution brief before it can recommend a concrete host or runtime path."
  }

  def build(brief, opts \\ [])

  def build(%ExecutionBrief{} = brief, opts), do: build(ExecutionBrief.to_map(brief), opts)

  def build(brief, opts) when is_map(brief) do
    posture = ExecutionPosture.build(brief)
    availability = availability(opts)
    strategy = strategy(brief, posture)

    case ranked_candidates(strategy, brief, availability) do
      [] ->
        Map.put(
          @undecided,
          "rationale",
          "CK could not match this brief to a shipped attach client or runtime export yet."
        )

      [{_score, best} | rest] ->
        %{
          "strategy" => strategy,
          "recommended_integration" => summarize(best, availability),
          "alternatives" =>
            rest
            |> Enum.map(&elem(&1, 1))
            |> Enum.take(2)
            |> Enum.map(&summarize(&1, availability)),
          "rationale" => rationale(strategy, best, brief, posture, availability)
        }
    end
  end

  def build(_brief, _opts), do: @undecided

  defp strategy(brief, posture) do
    cond do
      explicit_runtime_intent?(brief) and typed_runtime_candidate?(brief, posture) ->
        "headless_runtime"

      explicit_runtime_intent?(brief) and virtual_workspace_runtime_candidate?(brief, posture) ->
        "headless_runtime"

      approval_heavy?(brief) ->
        "attach_client"

      typed_runtime_candidate?(brief, posture) ->
        "headless_runtime"

      posture["shell_role"] == "broad_fallback_only" ->
        "attach_client"

      true ->
        "attach_client"
    end
  end

  defp ranked_candidates("attach_client", brief, availability) do
    AgentIntegration.attach_catalog()
    |> Enum.map(&{attach_score(&1, brief, availability), &1})
    |> Enum.sort_by(fn {score, integration} -> {score, integration.id} end, :desc)
  end

  defp ranked_candidates("headless_runtime", brief, availability) do
    AgentIntegration.runtime_export_catalog()
    |> Enum.map(&{runtime_score(&1, brief, availability), &1})
    |> Enum.sort_by(fn {score, integration} -> {score, integration.id} end, :desc)
  end

  defp ranked_candidates(_strategy, _brief, _availability), do: []

  defp summarize(integration, availability) do
    %{
      "id" => integration.id,
      "label" => integration.label,
      "support_class" => integration.support_class,
      "phase_model" => integration.phase_model,
      "review_experience" => integration.review_experience,
      "runtime_transport" => integration.runtime_transport,
      "runtime_auth_owner" => integration.runtime_auth_owner,
      "attach_command" => integration.attach_command,
      "runtime_export_command" => integration.runtime_export_command,
      "availability" => availability_label(integration, availability)
    }
  end

  defp rationale("attach_client", integration, brief, posture, availability) do
    review_note =
      if approval_heavy?(brief),
        do: "The brief already carries review or approval pressure.",
        else:
          "The execution posture still benefits from a host with native or browser-backed review checkpoints."

    availability_note =
      case availability_label(integration, availability) do
        "attached" -> " It is already attached in this workspace."
        "configured" -> " CK also sees matching runtime or provider configuration for it."
        _ -> ""
      end

    "#{review_note} #{integration.label} keeps CK in an attach-first path with #{integration.review_experience} and #{integration.phase_model}, while shell remains #{posture["shell_role"]}.#{availability_note}"
  end

  defp rationale("headless_runtime", integration, _brief, posture, availability) do
    availability_note =
      case availability_label(integration, availability) do
        "configured" ->
          " CK already has provider or runtime configuration that can support this path."

        _ ->
          ""
      end

    "#{integration.label} is the best fit when CK should lean into typed execution outside the transcript. It preserves #{posture["api_execution_surface"]} for large API or MCP-style work and leaves shell as #{posture["shell_role"]}.#{availability_note}"
  end

  defp rationale(_strategy, _integration, _brief, _posture, _availability),
    do: @undecided["rationale"]

  defp attach_score(integration, brief, availability) do
    brief_provider = compiler_provider(brief)
    attached_ids = availability.attached_ids

    review_score =
      case integration.review_experience do
        "native_review" -> 5
        "browser_review" -> 3
        _ -> 0
      end

    phase_score =
      case integration.phase_model do
        "host_plan_mode" -> 5
        "file_plan_mode" -> 4
        "review_only" -> 1
        _ -> 0
      end

    execution_score =
      case integration.execution_support do
        "direct" -> 3
        "handoff" -> 1
        _ -> 0
      end

    session_score =
      if is_map(integration.runtime_session_support) and
           Map.get(integration.runtime_session_support, "resume"),
         do: 1,
         else: 0

    provider_score =
      case runtime_provider(integration.id, availability.project_root) do
        provider when provider != nil and provider == brief_provider -> 3
        _ -> 0
      end

    auth_score = if integration.runtime_auth_owner == "agent", do: 1, else: 0

    availability_score =
      cond do
        MapSet.member?(attached_ids, integration.id) -> 12
        MapSet.size(attached_ids) > 0 -> -2
        true -> 0
      end

    review_score + phase_score + execution_score + session_score + provider_score + auth_score +
      availability_score
  end

  defp runtime_score(integration, brief, availability) do
    base_score =
      case integration.id do
        "cloudflare-workers" -> 8
        "executor" -> 4
        "virtual-bash" -> 4
        "open-swe" -> 5
        "devin" -> 4
        _ -> 1
      end

    api_score = if api_runtime_candidate?(brief), do: 3, else: 0

    cloudflare_bonus =
      if integration.id == "cloudflare-workers" and mentions?(brief, ["cloudflare", "workers"]),
        do: 3,
        else: 0

    executor_bonus =
      if integration.id == "executor" and
           mentions?(brief, ["executor"]),
         do: 6,
         else: 0

    executor_discovery_bonus =
      if integration.id == "executor" and
           mentions?(brief, ["openapi", "graphql", "discovery", "schema"]),
         do: 2,
         else: 0

    virtual_bash_bonus =
      if integration.id == "virtual-bash" and
           mentions?(brief, ["bash", "virtual workspace", "filesystem", "repo", "grep", "find"]),
         do: 6,
         else: 0

    virtual_bash_discovery_bonus =
      if integration.id == "virtual-bash" and virtual_workspace_candidate?(brief),
        do: 2,
        else: 0

    approval_penalty = if approval_heavy?(brief), do: -4, else: 0

    config_score =
      case availability_label(integration, availability) do
        "configured" -> 4
        _ -> 0
      end

    base_score + api_score + cloudflare_bonus + executor_bonus + executor_discovery_bonus +
      virtual_bash_bonus + virtual_bash_discovery_bonus + approval_penalty + config_score
  end

  defp typed_runtime_candidate?(brief, posture) do
    posture["api_execution_surface"] in ["typed_runtime", "typed_runtime_or_shell"] and
      api_runtime_candidate?(brief) and
      (explicit_runtime_intent?(brief) or not approval_heavy?(brief))
  end

  defp virtual_workspace_runtime_candidate?(brief, posture) do
    posture["exploration_surface"] == "virtual_workspace" and
      posture["shell_role"] in ["repo_local_fallback", "broad_fallback_only"] and
      virtual_workspace_candidate?(brief)
  end

  defp api_runtime_candidate?(brief), do: mentions?(brief, @api_runtime_keywords)
  defp virtual_workspace_candidate?(brief), do: mentions?(brief, @virtual_workspace_keywords)

  defp explicit_runtime_intent?(brief),
    do:
      mentions?(
        brief,
        ~w(runtime runtimes export exported cloudflare workers executor virtual bash workspace sandbox)
      )

  defp approval_heavy?(brief), do: mentions?(brief, @approval_keywords)

  defp mentions?(brief, terms) do
    brief
    |> searchable_text()
    |> then(fn text -> Enum.any?(terms, &String.contains?(text, &1)) end)
  end

  defp searchable_text(brief) do
    [
      fetch_string(brief, "idea"),
      fetch_string(brief, "objective"),
      fetch_string(brief, "data_summary"),
      fetch_string(brief, "recommended_stack"),
      fetch_string(brief, "next_step"),
      list_text(fetch_value(brief, "compliance")),
      list_text(fetch_value(brief, "acceptance_criteria")),
      list_text(fetch_value(brief, "open_questions")),
      nested_constraint_text(brief)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp nested_constraint_text(brief) do
    brief
    |> fetch_value("compiler")
    |> case do
      compiler when is_map(compiler) ->
        compiler
        |> fetch_value("interview_answers")
        |> case do
          answers when is_map(answers) -> fetch_string(answers, "constraints")
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp runtime_provider(integration_id, project_root) do
    case RuntimeRegistry.provider_hint(integration_id, project_root) do
      %{"provider" => provider} when is_binary(provider) -> provider
      _ -> nil
    end
  end

  defp compiler_provider(brief) do
    brief
    |> fetch_value("compiler")
    |> case do
      compiler when is_map(compiler) -> fetch_string(compiler, "provider")
      _ -> nil
    end
  end

  defp list_text(value) when is_list(value), do: Enum.join(Enum.map(value, &to_string/1), " ")
  defp list_text(_value), do: nil

  defp fetch_string(map, key) do
    case fetch_value(map, key) do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp fetch_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, known_atom_key(key))
  end

  defp known_atom_key("idea"), do: :idea
  defp known_atom_key("objective"), do: :objective
  defp known_atom_key("data_summary"), do: :data_summary
  defp known_atom_key("recommended_stack"), do: :recommended_stack
  defp known_atom_key("next_step"), do: :next_step
  defp known_atom_key("compliance"), do: :compliance
  defp known_atom_key("acceptance_criteria"), do: :acceptance_criteria
  defp known_atom_key("open_questions"), do: :open_questions
  defp known_atom_key("compiler"), do: :compiler
  defp known_atom_key("interview_answers"), do: :interview_answers
  defp known_atom_key("constraints"), do: :constraints
  defp known_atom_key("provider"), do: :provider
  defp known_atom_key(_key), do: nil

  defp availability(opts) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())

    status =
      cond do
        is_map(opts[:provider_status]) ->
          opts[:provider_status]

        true ->
          ProviderBroker.status(project_root)
      end

    attached_ids =
      status
      |> Map.get("attached_agents", [])
      |> Enum.map(fn
        %{"id" => id} -> normalize_id(id)
        %{id: id} -> normalize_id(id)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    runtime_hint_ids =
      status
      |> Map.get("runtime_hints", [])
      |> Enum.map(fn
        %{"agent_id" => id} -> normalize_id(id)
        %{agent_id: id} -> normalize_id(id)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    exported_runtime_ids =
      opts
      |> Keyword.get(:available_runtimes, detect_exported_runtimes(project_root))
      |> Enum.map(&normalize_id/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    %{
      project_root: project_root,
      status: status,
      attached_ids: attached_ids,
      runtime_hint_ids: runtime_hint_ids,
      exported_runtime_ids: exported_runtime_ids
    }
  end

  defp availability_label(integration, availability) do
    cond do
      MapSet.member?(availability.attached_ids, integration.id) ->
        "attached"

      integration.support_class == "headless_runtime" and
          (MapSet.member?(availability.exported_runtime_ids, integration.id) or
             MapSet.member?(availability.runtime_hint_ids, integration.id)) ->
        "configured"

      MapSet.member?(availability.runtime_hint_ids, integration.id) ->
        "configured"

      true ->
        "catalog"
    end
  end

  defp normalize_id(id) when is_binary(id) do
    id
    |> String.trim()
    |> String.downcase()
    |> String.replace("_", "-")
  end

  defp normalize_id(id) when is_atom(id), do: id |> Atom.to_string() |> normalize_id()
  defp normalize_id(_id), do: nil

  defp detect_exported_runtimes(project_root) do
    root = Path.expand(project_root)

    AgentIntegration.runtime_export_catalog()
    |> Enum.filter(fn integration ->
      is_binary(integration.preferred_target) and
        File.dir?(Path.join([root, "controlkeel", "dist", integration.preferred_target]))
    end)
    |> Enum.map(& &1.id)
  end
end
